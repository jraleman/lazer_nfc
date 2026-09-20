/**************************************************************************/
/*  lazer_nfc.h                                                           */
/*  LaZer NFC - game-owned Godot iOS Core NFC reader.                     */
/**************************************************************************/

#ifndef LAZER_NFC_H
#define LAZER_NFC_H

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/string/ustring.h"

/**
 * A Godot singleton mirroring the game's Android reader contract:
 * is_supported() / is_enabled() / enable_reader() / disable_reader() plus the
 * tag_discovered, adapter_state and reader_error signals. Core NFC adds two
 * optional surfaces the Android adapter does not need - set_prompt() for the
 * system scanning sheet and the reader_cancelled signal for its Cancel button.
 * No NDEF payload is read, no tag is written, and no tag UID is logged.
 */
class LazerNfc : public Object {
	GDCLASS(LazerNfc, Object);

	static LazerNfc *singleton;

	// A retained LazerNfcReader. Ownership is bridged explicitly in lazer_nfc.mm
	// so this header stays usable from plain C++ translation units.
	void *reader = nullptr;

protected:
	static void _bind_methods();

public:
	static LazerNfc *get_singleton();

	bool is_supported() const;
	bool is_enabled() const;
	void enable_reader();
	void disable_reader();

	// Text shown on the system scanning sheet; safe to call while scanning.
	void set_prompt(const String &p_text);
	// True when scanning takes over the screen, as Core NFC always does.
	bool is_modal() const;

	// Called by the reader once it has already hopped to the main thread.
	void dispatch_tag(const String &p_uid, int64_t p_age_ms);
	void dispatch_adapter_state(bool p_enabled);
	void dispatch_reader_error(const String &p_message);
	void dispatch_reader_cancelled();

	LazerNfc();
	~LazerNfc();
};

#endif // LAZER_NFC_H
