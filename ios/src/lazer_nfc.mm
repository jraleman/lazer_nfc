/**************************************************************************/
/*  lazer_nfc.mm                                                          */
/*  LaZer NFC - Core NFC tag-identifier reader for the Godot iOS export.  */
/**************************************************************************/

#include "lazer_nfc.h"

#include "core/object/class_db.h"
#include "core/variant/variant.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <TargetConditionals.h>
#include <time.h>

#if !TARGET_OS_SIMULATOR
#import <CoreNFC/CoreNFC.h>
#define LAZER_NFC_CORE_AVAILABLE 1
#else
// Core NFC has no simulator radio. The simulator slice of the xcframework
// still has to compile and link, so it reports unsupported hardware instead.
#define LAZER_NFC_CORE_AVAILABLE 0
#endif

// Keep aligned with NFC_LATENCY_COMP_MS in lazer_nfc_options.gd and with the
// Android reader's RF_LATENCY_MS, so one age contract covers both platforms.
static const int64_t LAZER_NFC_RF_LATENCY_MS = 80;
// Core NFC has no presence check, so a tag left resting on the phone would be
// rediscovered every restart. Connecting pins the tag, and NFCTag.isAvailable
// then reports RF presence, which is how this reader reproduces Android's
// EXTRA_READER_PRESENCE_CHECK_DELAY rather than answering a round repeatedly.
static const double LAZER_NFC_PRESENCE_POLL_S = 0.25;
// A tag whose isAvailable never clears must not hold the field forever, or a
// stale reading would block every later tap. Rediscovering the pinned tag is
// harmless because its identifier is suppressed until it truly leaves, so this
// ceiling can stay short enough to recover quickly.
static const double LAZER_NFC_PRESENCE_MAX_S = 5.0;
// Apple's own tag-reader sample waits this long before restarting polling.
static const double LAZER_NFC_RESTART_POLLING_S = 0.5;
// How long a pinned identifier survives without being seen again. It only
// matters when removal is never observed: a tag that reports itself present
// forever, or one the reader could not connect to. Without this the tag could
// never be scanned a second time.
static const double LAZER_NFC_PIN_EXPIRY_S = 8.0;
// A timed-out or unexpectedly terminated session is reopened after a pause;
// Core NFC rejects sessions started back to back with "system is busy".
static const double LAZER_NFC_RENEW_DELAY_S = 0.6;
static const double LAZER_NFC_BUSY_DELAY_S = 1.5;
static const int LAZER_NFC_BUSY_RETRIES = 3;

static NSString *const LAZER_NFC_DEFAULT_PROMPT =
		@"Hold the upper back of your iPhone against a laboratory tag.";

static int64_t lazer_nfc_uptime_ms() {
	return (int64_t)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000ULL);
}

/**************************************************************************/
/* Objective-C reader                                                     */
/**************************************************************************/

@interface LazerNfcReader : NSObject
#if LAZER_NFC_CORE_AVAILABLE
						   <NFCTagReaderSessionDelegate>
#endif

- (instancetype)initWithOwner:(LazerNfc *)owner;
- (BOOL)isSupported;
- (BOOL)isEnabled;
- (void)enable;
- (void)disable;
- (void)setPrompt:(NSString *)prompt;
- (void)detachOwner;
- (void)shutdown;

@end

@implementation LazerNfcReader {
	LazerNfc *_owner;
	NSString *_prompt;
	BOOL _requested;
	BOOL _applicationActive;
	BOOL _radioDisabled;
	BOOL _shutdown;
	int _busyRetries;
#if LAZER_NFC_CORE_AVAILABLE
	NFCTagReaderSession *_session;
	dispatch_queue_t _queue;
	// The session this reader invalidated itself, so its delegate callback is
	// never mistaken for a device fault or a player decision.
	NFCTagReaderSession *_closingSession;
	// Identifier of the tag currently resting in the field. Core NFC has no
	// presence check, so a tag left on the phone is rediscovered whenever
	// polling restarts or the session renews; suppressing this identifier
	// until the tag actually leaves is what keeps one tap worth one answer.
	NSString *_pinnedUid;
	// Bumped every time the pinned tag is seen, so an expiry scheduled for an
	// older sighting cannot unpin a tag that is still on the phone.
	uint64_t _pinGeneration;
#endif
}

- (instancetype)initWithOwner:(LazerNfc *)owner {
	self = [super init];
	if (self) {
		_owner = owner;
		_prompt = LAZER_NFC_DEFAULT_PROMPT;
		_requested = NO;
		_radioDisabled = NO;
		_shutdown = NO;
		_busyRetries = 0;
		_applicationActive = YES;
#if LAZER_NFC_CORE_AVAILABLE
		_session = nil;
		_closingSession = nil;
		_pinnedUid = nil;
		_pinGeneration = 0;
		_queue = dispatch_queue_create("com.deskcansaw.lazernfc.reader", DISPATCH_QUEUE_SERIAL);
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		// Only real backgrounding stops the reader. Presenting the system
		// scanning sheet can resign the active state, which must not be read
		// as the player leaving the game.
		[center addObserver:self
				   selector:@selector(onApplicationBackground:)
					   name:UIApplicationDidEnterBackgroundNotification
					 object:nil];
		[center addObserver:self
				   selector:@selector(onApplicationForeground:)
					   name:UIApplicationDidBecomeActiveNotification
					 object:nil];
#endif
	}
	return self;
}

- (void)dealloc {
#if LAZER_NFC_CORE_AVAILABLE
	[[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
}

/* -------------------------------------------------------------------- */
/* Main-thread helpers                                                   */
/* -------------------------------------------------------------------- */

- (void)runOnMain:(dispatch_block_t)block {
	if ([NSThread isMainThread]) {
		block();
	} else {
		dispatch_async(dispatch_get_main_queue(), block);
	}
}

- (void)emitAdapterState:(BOOL)enabled {
	[self runOnMain:^{
		if (!self->_shutdown && self->_owner != nullptr) {
			self->_owner->dispatch_adapter_state(enabled ? true : false);
		}
	}];
}

- (void)emitError:(NSString *)message {
	NSString *detail = message.length > 0 ? message : @"The NFC reader stopped unexpectedly.";
	[self runOnMain:^{
		if (!self->_shutdown && self->_owner != nullptr) {
			self->_owner->dispatch_reader_error(String::utf8([detail UTF8String]));
		}
	}];
}

- (void)emitCancelled {
	[self runOnMain:^{
		if (!self->_shutdown && self->_owner != nullptr) {
			self->_owner->dispatch_reader_cancelled();
		}
	}];
}

/* -------------------------------------------------------------------- */
/* Public surface                                                        */
/* -------------------------------------------------------------------- */

- (BOOL)isSupported {
#if LAZER_NFC_CORE_AVAILABLE
	return NFCTagReaderSession.readingAvailable ? YES : NO;
#else
	return NO;
#endif
}

- (BOOL)isEnabled {
	return [self isSupported] && !_radioDisabled;
}

- (void)enable {
	[self runOnMain:^{
		if (self->_shutdown) {
			return;
		}
		self->_requested = YES;
		self->_busyRetries = 0;
		[self openSession];
	}];
}

- (void)disable {
	[self runOnMain:^{
		self->_requested = NO;
#if LAZER_NFC_CORE_AVAILABLE
		// A deliberate stop ends the tap that pinned the tag, matching the
		// Android reader, where re-enabling reader mode re-reports a tag that
		// is still resting on the phone.
		self->_pinnedUid = nil;
#endif
		[self closeSession];
	}];
}

- (void)setPrompt:(NSString *)prompt {
	NSString *text = prompt.length > 0 ? [prompt copy] : LAZER_NFC_DEFAULT_PROMPT;
	[self runOnMain:^{
		self->_prompt = text;
#if LAZER_NFC_CORE_AVAILABLE
		// Apple documents alertMessage as writable from any thread while the
		// session is valid; keeping it on main keeps the state single-owner.
		if (self->_session != nil) {
			self->_session.alertMessage = text;
		}
#endif
	}];
}

- (void)detachOwner {
	// The C++ owner is destroyed the moment this returns, so the back pointer
	// has to be dropped synchronously rather than on a queued main-thread
	// block. Godot destroys its singletons on the main thread, which is what
	// keeps this store ordered against the readers above.
	_owner = nullptr;
	_shutdown = YES;
}

- (void)shutdown {
	[self runOnMain:^{
		self->_shutdown = YES;
		self->_requested = NO;
		self->_owner = nullptr;
#if LAZER_NFC_CORE_AVAILABLE
		self->_pinnedUid = nil;
#endif
		[self closeSession];
	}];
}

/* -------------------------------------------------------------------- */
/* Session lifecycle                                                     */
/* -------------------------------------------------------------------- */

- (void)openSession {
#if LAZER_NFC_CORE_AVAILABLE
	if (_shutdown || !_requested || !_applicationActive || _session != nil) {
		return;
	}
	if (![self isSupported]) {
		_requested = NO;
		[self emitAdapterState:NO];
		return;
	}
	// FeliCa is deliberately absent: polling with NFCPollingISO18092 requires
	// com.apple.developer.nfc.readersession.felica.systemcodes in Info.plist,
	// and without an enumerated system code Core NFC kills the whole session
	// with a security violation rather than just skipping FeliCa tags.
	NFCPollingOption polling = (NFCPollingOption)(NFCPollingISO14443 | NFCPollingISO15693);
	NFCTagReaderSession *session = [[NFCTagReaderSession alloc] initWithPollingOption:polling
																			delegate:self
																			   queue:_queue];
	if (session == nil) {
		_requested = NO;
		[self emitError:@"Could not open an NFC reader session."];
		return;
	}
	session.alertMessage = _prompt;
	_session = session;
	[session beginSession];
#endif
}

- (void)closeSession {
#if LAZER_NFC_CORE_AVAILABLE
	NFCTagReaderSession *session = _session;
	if (session == nil) {
		return;
	}
	_session = nil;
	_closingSession = session;
	[session invalidateSession];
#endif
}

#if LAZER_NFC_CORE_AVAILABLE
- (void)scheduleReopenAfter:(double)delay {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
				[self openSession];
			});
}

/// Records the tag currently resting in the field. Must run on main.
- (void)pinUid:(NSString *)uid {
	_pinnedUid = uid;
	_pinGeneration += 1;
	uint64_t generation = _pinGeneration;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
						  (int64_t)(LAZER_NFC_PIN_EXPIRY_S * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
				if (self->_pinGeneration == generation) {
					self->_pinnedUid = nil;
				}
			});
}

/// Clears the pin once the tag is known to have left. Must run on main.
- (void)unpinUid:(NSString *)uid {
	if (_pinnedUid != nil && [_pinnedUid isEqualToString:uid]) {
		_pinnedUid = nil;
		_pinGeneration += 1;
	}
}
#endif

- (void)onApplicationBackground:(NSNotification *)notification {
	[self runOnMain:^{
		self->_applicationActive = NO;
		[self closeSession];
	}];
}

- (void)onApplicationForeground:(NSNotification *)notification {
	[self runOnMain:^{
		if (self->_shutdown) {
			return;
		}
		self->_applicationActive = YES;
		// Airplane mode is the only way an iPhone reports a disabled radio;
		// returning to the foreground is the moment to look again.
		if (self->_radioDisabled && [self isSupported]) {
			self->_radioDisabled = NO;
			[self emitAdapterState:YES];
		}
		[self openSession];
	}];
}

/* -------------------------------------------------------------------- */
/* NFCTagReaderSessionDelegate                                           */
/* -------------------------------------------------------------------- */

#if LAZER_NFC_CORE_AVAILABLE

- (void)tagReaderSessionDidBecomeActive:(NFCTagReaderSession *)session {
	[self runOnMain:^{
		if (self->_session == session) {
			self->_busyRetries = 0;
		}
	}];
}

- (void)tagReaderSession:(NFCTagReaderSession *)session
		   didDetectTags:(NSArray<__kindof id<NFCTag>> *)tags {
	int64_t discovered_at = lazer_nfc_uptime_ms();
	id<NFCTag> found = nil;
	NSString *uid = nil;
	for (id<NFCTag> tag in tags) {
		uid = [LazerNfcReader identifierForTag:tag];
		if (uid != nil) {
			found = tag;
			break;
		}
	}
	if (uid == nil) {
		[self runOnMain:^{
			if (self->_session == session && self->_requested && !self->_shutdown) {
				[self emitError:@"A tag without a readable identifier was detected."];
			}
		}];
		[self restartPolling:session after:LAZER_NFC_RESTART_POLLING_S];
		return;
	}

	NSString *detected = uid;
	[self runOnMain:^{
		if (self->_shutdown || self->_owner == nullptr || self->_session != session
				|| !self->_requested) {
			return;
		}
		// The tag resting in the field is rediscovered every time polling
		// restarts and every time the session renews. Only a fresh tap, after
		// the previous one was seen to leave, earns an answer.
		BOOL repeat = self->_pinnedUid != nil && [self->_pinnedUid isEqualToString:detected];
		[self pinUid:detected];
		if (repeat) {
			return;
		}
		int64_t age = MAX((int64_t)0, lazer_nfc_uptime_ms() - discovered_at) + LAZER_NFC_RF_LATENCY_MS;
		self->_owner->dispatch_tag(String::utf8([detected UTF8String]), age);
	}];

	// Holding the tag connected is what lets the reader watch for its removal.
	// Failing to connect is not fatal: the identifier already arrived with the
	// polling response, and the pin expires on its own.
	[session connectToTag:found
		completionHandler:^(NSError *_Nullable error) {
			if (error != nil) {
				[self restartPolling:session after:LAZER_NFC_RESTART_POLLING_S];
				return;
			}
			[self waitForRemovalOfTag:found
								  uid:detected
							  session:session
							 deadline:lazer_nfc_uptime_ms()
									  + (int64_t)(LAZER_NFC_PRESENCE_MAX_S * 1000.0)];
		}];
}

/// Polls RF presence on the delegate queue until the tag leaves, then reopens
/// the field for the next answer.
- (void)waitForRemovalOfTag:(id<NFCTag>)tag
						uid:(NSString *)uid
					session:(NFCTagReaderSession *)session
				   deadline:(int64_t)deadline {
	if (!tag.available) {
		[self runOnMain:^{
			[self unpinUid:uid];
		}];
		[self restartPolling:session after:0.0];
		return;
	}
	if (lazer_nfc_uptime_ms() >= deadline) {
		// The pin survives: if the tag really is still there it is rediscovered
		// and silently re-pinned, and if isAvailable was stuck the pin expires.
		[self restartPolling:session after:0.0];
		return;
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
						  (int64_t)(LAZER_NFC_PRESENCE_POLL_S * NSEC_PER_SEC)),
			_queue, ^{
				[self waitForRemovalOfTag:tag uid:uid session:session deadline:deadline];
			});
}

- (void)restartPolling:(NFCTagReaderSession *)session after:(double)delay {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
				if (self->_session == session && self->_requested && !self->_shutdown) {
					[session restartPolling];
				}
			});
}

- (void)tagReaderSession:(NFCTagReaderSession *)session didInvalidateWithError:(NSError *)error {
	[self runOnMain:^{
		[self handleInvalidation:session error:error];
	}];
}

- (void)handleInvalidation:(NFCTagReaderSession *)session error:(NSError *)error {
	if (_closingSession == session) {
		_closingSession = nil;
		return;
	}
	if (_session != session) {
		// A session this reader already replaced cannot revoke the live one.
		return;
	}
	_session = nil;
	if (_shutdown) {
		return;
	}
	NSInteger code = [error.domain isEqualToString:NFCErrorDomain] ? error.code : 0;
	switch (code) {
		case NFCReaderSessionInvalidationErrorUserCanceled: {
			// Dismissing the sheet is the iPhone's only in-scan escape, so it
			// is a deliberate request for keys and touch, never a failure.
			_requested = NO;
			[self emitCancelled];
		} break;
		case NFCReaderSessionInvalidationErrorSessionTimeout:
		case NFCReaderSessionInvalidationErrorSessionTerminatedUnexpectedly: {
			if (_requested && _applicationActive) {
				[self scheduleReopenAfter:LAZER_NFC_RENEW_DELAY_S];
			}
		} break;
		case NFCReaderSessionInvalidationErrorSystemIsBusy: {
			if (_requested && _applicationActive && _busyRetries < LAZER_NFC_BUSY_RETRIES) {
				_busyRetries += 1;
				[self scheduleReopenAfter:LAZER_NFC_BUSY_DELAY_S];
			} else {
				_requested = NO;
				[self emitError:@"The NFC reader is busy. Keys and touch remain available."];
			}
		} break;
		case NFCReaderErrorRadioDisabled: {
			_requested = NO;
			_radioDisabled = YES;
			[self emitAdapterState:NO];
		} break;
		default: {
			_requested = NO;
			[self emitError:error.localizedDescription];
		} break;
	}
}

/* -------------------------------------------------------------------- */
/* Identifiers                                                           */
/* -------------------------------------------------------------------- */

+ (NSString *)identifierForTag:(id<NFCTag>)tag {
	NSData *identifier = nil;
	switch (tag.type) {
		case NFCTagTypeMiFare:
			identifier = [tag asNFCMiFareTag].identifier;
			break;
		case NFCTagTypeISO7816Compatible:
			identifier = [tag asNFCISO7816Tag].identifier;
			break;
		case NFCTagTypeISO15693:
			identifier = [tag asNFCISO15693Tag].identifier;
			break;
		default:
			// FeliCa is unreachable: openSession never polls ISO18092.
			break;
	}
	if (identifier == nil || identifier.length == 0 || identifier.length > 32) {
		return nil;
	}
	static const char hex[] = "0123456789abcdef";
	const uint8_t *bytes = (const uint8_t *)identifier.bytes;
	NSMutableString *encoded = [NSMutableString stringWithCapacity:identifier.length * 2];
	for (NSUInteger index = 0; index < identifier.length; index++) {
		uint8_t value = bytes[index];
		[encoded appendFormat:@"%c%c", hex[value >> 4], hex[value & 0x0f]];
	}
	return encoded;
}

#endif // LAZER_NFC_CORE_AVAILABLE

@end

/**************************************************************************/
/* Godot singleton                                                        */
/**************************************************************************/

LazerNfc *LazerNfc::singleton = nullptr;

LazerNfc *LazerNfc::get_singleton() {
	return singleton;
}

void LazerNfc::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &LazerNfc::is_supported);
	ClassDB::bind_method(D_METHOD("is_enabled"), &LazerNfc::is_enabled);
	ClassDB::bind_method(D_METHOD("enable_reader"), &LazerNfc::enable_reader);
	ClassDB::bind_method(D_METHOD("disable_reader"), &LazerNfc::disable_reader);
	ClassDB::bind_method(D_METHOD("set_prompt", "text"), &LazerNfc::set_prompt);
	ClassDB::bind_method(D_METHOD("is_modal"), &LazerNfc::is_modal);

	ADD_SIGNAL(MethodInfo("tag_discovered",
			PropertyInfo(Variant::STRING, "uid"), PropertyInfo(Variant::INT, "age_ms")));
	ADD_SIGNAL(MethodInfo("adapter_state", PropertyInfo(Variant::BOOL, "enabled")));
	ADD_SIGNAL(MethodInfo("reader_error", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("reader_cancelled"));
}

LazerNfc::LazerNfc() {
	singleton = this;
	LazerNfcReader *instance = [[LazerNfcReader alloc] initWithOwner:this];
	reader = (__bridge_retained void *)instance;
}

LazerNfc::~LazerNfc() {
	if (reader != nullptr) {
		LazerNfcReader *instance = (__bridge_transfer LazerNfcReader *)reader;
		reader = nullptr;
		// Drop the back pointer before this object dies, then let the reader
		// tear its session down; any block already queued sees a null owner.
		[instance detachOwner];
		[instance shutdown];
	}
	if (singleton == this) {
		singleton = nullptr;
	}
}

bool LazerNfc::is_supported() const {
	if (reader == nullptr) {
		return false;
	}
	return [(__bridge LazerNfcReader *)reader isSupported] ? true : false;
}

bool LazerNfc::is_enabled() const {
	if (reader == nullptr) {
		return false;
	}
	return [(__bridge LazerNfcReader *)reader isEnabled] ? true : false;
}

void LazerNfc::enable_reader() {
	if (reader != nullptr) {
		[(__bridge LazerNfcReader *)reader enable];
	}
}

void LazerNfc::disable_reader() {
	if (reader != nullptr) {
		[(__bridge LazerNfcReader *)reader disable];
	}
}

void LazerNfc::set_prompt(const String &p_text) {
	if (reader == nullptr) {
		return;
	}
	NSString *text = [NSString stringWithUTF8String:p_text.utf8().get_data()];
	[(__bridge LazerNfcReader *)reader setPrompt:text];
}

bool LazerNfc::is_modal() const {
	// Core NFC always presents its own scanning sheet; it cannot be suppressed.
#if LAZER_NFC_CORE_AVAILABLE
	return true;
#else
	return false;
#endif
}

void LazerNfc::dispatch_tag(const String &p_uid, int64_t p_age_ms) {
	emit_signal("tag_discovered", p_uid, p_age_ms);
}

void LazerNfc::dispatch_adapter_state(bool p_enabled) {
	emit_signal("adapter_state", p_enabled);
}

void LazerNfc::dispatch_reader_error(const String &p_message) {
	emit_signal("reader_error", p_message);
}

void LazerNfc::dispatch_reader_cancelled() {
	emit_signal("reader_cancelled");
}
