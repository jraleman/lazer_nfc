package com.deskcansaw.lazernfc;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * A Godot v2 reader-mode plugin. The game request and Android lifecycle are independent gates.
 * No NDEF data is read, no tag is written, and no tag UID is logged.
 */
public final class LazerNfc extends GodotPlugin {
	private static final String LOG_TAG = "LazerNfc";
	// Keep aligned with NFC_LATENCY_COMP_MS in lazer_nfc_options.gd.
	private static final long RF_LATENCY_MS = 80L;
	private static final int READER_FLAGS =
		NfcAdapter.FLAG_READER_NFC_A
		| NfcAdapter.FLAG_READER_NFC_B
		| NfcAdapter.FLAG_READER_NFC_F
		| NfcAdapter.FLAG_READER_NFC_V
		| NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
		| NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS;
	private static final char[] HEX = "0123456789abcdef".toCharArray();

	private final AtomicBoolean readerRequested = new AtomicBoolean(false);
	private final AtomicLong readerGeneration = new AtomicLong(0L);
	private final AtomicLong lifecycleGeneration = new AtomicLong(0L);
	private final Object requestLock = new Object();
	private volatile boolean lifecycleActive;
	private volatile boolean godotReady;
	private volatile boolean destroyed;
	private volatile NfcAdapter adapter;
	private volatile Activity ownerActivity;

	// These fields, and every Android reader/receiver operation, belong to the UI thread.
	private Activity readerActivity;
	private long enabledGeneration = -1L;
	private Context receiverContext;

	private final BroadcastReceiver adapterReceiver = new BroadcastReceiver() {
		@Override
		public void onReceive(Context context, Intent intent) {
			if (destroyed || !lifecycleActive
				|| !NfcAdapter.ACTION_ADAPTER_STATE_CHANGED.equals(intent.getAction())) {
				return;
			}
			boolean enabled = intent.getIntExtra(NfcAdapter.EXTRA_ADAPTER_STATE,
				NfcAdapter.STATE_OFF) == NfcAdapter.STATE_ON;
			long generation;
			synchronized (requestLock) {
				if (!enabled) {
					readerRequested.set(false);
				}
				generation = readerGeneration.incrementAndGet();
			}
			Activity activity = ownerActivity;
			if (activity != null) {
				activity.runOnUiThread(() -> reconcileReader(activity, generation));
			}
			emitAdapterState(enabled);
		}
	};

	/** The runtime discovers this constructor through the v2 manifest metadata. */
	public LazerNfc(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "LazerNfc";
	}

	@Override
	public Set<SignalInfo> getPluginSignals() {
		Set<SignalInfo> signals = new HashSet<>();
		signals.add(new SignalInfo("tag_discovered", String.class, Long.class));
		signals.add(new SignalInfo("adapter_state", Boolean.class));
		signals.add(new SignalInfo("reader_error", String.class));
		return signals;
	}

	@Override
	public View onMainCreate(Activity activity) {
		ownerActivity = activity;
		getAdapter();
		return null;
	}

	@Override
	public void onGodotSetupCompleted() {
		godotReady = true;
		emitAdapterState();
	}

	/** Missing hardware is a normal fallback condition, not a failed plugin. */
	@UsedByGodot
	public boolean is_supported() {
		return getAdapter() != null;
	}

	/** NFC is a normal manifest permission; Android exposes no runtime consent dialog for it. */
	@UsedByGodot
	public boolean is_enabled() {
		NfcAdapter current = getAdapter();
		if (current == null) {
			return false;
		}
		try {
			return current.isEnabled();
		} catch (SecurityException exception) {
			reportError(readerGeneration.get(), "query NFC adapter", exception);
			return false;
		}
	}

	/** Called only by a live game's source; resuming the activity is not itself a request. */
	@UsedByGodot
	public void enable_reader() {
		long generation;
		synchronized (requestLock) {
			if (destroyed) {
				return;
			}
			readerRequested.set(true);
			generation = readerGeneration.incrementAndGet();
		}
		queueReaderUpdate(generation);
	}

	/** Revoke callbacks immediately, even while the Android UI thread is busy. */
	@UsedByGodot
	public void disable_reader() {
		long generation;
		synchronized (requestLock) {
			readerRequested.set(false);
			generation = readerGeneration.incrementAndGet();
		}
		queueReaderUpdate(generation);
	}

	@Override
	public void onMainResume() {
		if (destroyed) {
			return;
		}
		Activity activity = getActivity();
		if (activity == null) {
			reportError(readerGeneration.get(), "resume NFC without an Android activity", null);
			return;
		}
		ownerActivity = activity;
		lifecycleActive = true;
		long lifecycle = lifecycleGeneration.incrementAndGet();
		readerGeneration.incrementAndGet();
		activity.runOnUiThread(() -> {
			if (destroyed || !lifecycleActive || lifecycle != lifecycleGeneration.get()) {
				return;
			}
			registerReceiver(activity);
			reconcileReader(activity, readerGeneration.get());
			emitAdapterState();
		});
	}

	@Override
	public void onMainPause() {
		lifecycleActive = false;
		long lifecycle = lifecycleGeneration.incrementAndGet();
		long generation = readerGeneration.incrementAndGet();
		Activity activity = ownerActivity;
		if (activity != null) {
			activity.runOnUiThread(() -> {
				if (lifecycle != lifecycleGeneration.get()) {
					return;
				}
				disableReaderOnUiThread(generation);
				unregisterReceiver();
			});
		}
	}

	@Override
	public void onMainDestroy() {
		destroyed = true;
		godotReady = false;
		lifecycleActive = false;
		readerRequested.set(false);
		lifecycleGeneration.incrementAndGet();
		long generation = readerGeneration.incrementAndGet();
		Activity activity = ownerActivity;
		if (activity != null) {
			activity.runOnUiThread(() -> {
				disableReaderOnUiThread(generation);
				unregisterReceiver();
				ownerActivity = null;
			});
		}
	}

	@Override
	public void onGodotTerminating() {
		godotReady = false;
		disable_reader();
	}

	private NfcAdapter getAdapter() {
		NfcAdapter current = adapter;
		Activity activity = getActivity();
		if (current == null && activity != null && !destroyed) {
			current = NfcAdapter.getDefaultAdapter(activity.getApplicationContext());
			adapter = current;
		}
		return current;
	}

	private void queueReaderUpdate(long generation) {
		Activity activity = ownerActivity;
		if (activity == null) {
			if (readerRequested.get() && !destroyed) {
				reportError(generation, "start NFC without an Android activity", null);
			}
			return;
		}
		activity.runOnUiThread(() -> reconcileReader(activity, generation));
	}

	private void reconcileReader(Activity activity, long generation) {
		if (generation != readerGeneration.get()) {
			return;
		}
		boolean shouldRead = !destroyed && lifecycleActive && readerRequested.get()
			&& activity == ownerActivity;
		if (shouldRead && !is_enabled()) {
			cancelReaderRequest(generation);
			shouldRead = false;
		}
		if (shouldRead && readerActivity == activity && enabledGeneration == generation) {
			return;
		}
		disableReaderOnUiThread(generation);
		if (!shouldRead) {
			return;
		}
		NfcAdapter current = getAdapter();
		if (current == null) {
			return;
		}
		Bundle options = new Bundle();
		options.putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 250);
		try {
			current.enableReaderMode(activity,
				tag -> onTagDiscovered(tag, generation), READER_FLAGS, options);
			readerActivity = activity;
			enabledGeneration = generation;
		} catch (SecurityException | IllegalStateException | UnsupportedOperationException exception) {
			cancelReaderRequest(generation);
			reportError(generation, "enable NFC reader mode", exception);
		}
	}

	private void cancelReaderRequest(long generation) {
		synchronized (requestLock) {
			if (generation == readerGeneration.get()) {
				readerRequested.set(false);
			}
		}
	}

	private void disableReaderOnUiThread(long generation) {
		Activity activity = readerActivity;
		NfcAdapter current = adapter;
		readerActivity = null;
		enabledGeneration = -1L;
		if (activity == null || current == null) {
			return;
		}
		try {
			current.disableReaderMode(activity);
		} catch (SecurityException | IllegalStateException | UnsupportedOperationException exception) {
			reportError(generation, "disable NFC reader mode", exception);
		}
	}

	private void onTagDiscovered(Tag tag, long generation) {
		long discoveredAt = SystemClock.elapsedRealtime();
		if (!canDeliver(generation)) {
			return;
		}
		byte[] identifier = tag.getId();
		if (identifier == null || identifier.length == 0 || identifier.length > 32) {
			reportError(generation, "read a tag without a supported hexadecimal UID", null);
			return;
		}
		char[] encoded = new char[identifier.length * 2];
		for (int index = 0; index < identifier.length; index++) {
			int value = identifier[index] & 0xff;
			encoded[index * 2] = HEX[value >>> 4];
			encoded[index * 2 + 1] = HEX[value & 0x0f];
		}
		String uid = new String(encoded);
		runOnRenderThread(() -> {
			if (!canDeliver(generation)) {
				return;
			}
			long age = Math.max(0L, SystemClock.elapsedRealtime() - discoveredAt) + RF_LATENCY_MS;
			emitSignal("tag_discovered", uid, age);
		});
	}

	private boolean canDeliver(long generation) {
		return godotReady && !destroyed && lifecycleActive && readerRequested.get()
			&& generation == readerGeneration.get();
	}

	private void registerReceiver(Activity activity) {
		if (receiverContext != null || getAdapter() == null) {
			return;
		}
		Context context = activity.getApplicationContext();
		IntentFilter filter = new IntentFilter(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED);
		try {
			if (Build.VERSION.SDK_INT >= 33) {
				// NFC may run under its own privileged UID. This is a protected system
				// broadcast; requiring the NFC permission further restricts its sender.
				context.registerReceiver(adapterReceiver, filter, Manifest.permission.NFC,
					null, Context.RECEIVER_EXPORTED);
			} else {
				context.registerReceiver(adapterReceiver, filter, Manifest.permission.NFC, null);
			}
			receiverContext = context;
		} catch (SecurityException | IllegalArgumentException exception) {
			reportError(readerGeneration.get(), "observe NFC adapter state", exception);
		}
	}

	private void unregisterReceiver() {
		Context context = receiverContext;
		receiverContext = null;
		if (context == null) {
			return;
		}
		try {
			context.unregisterReceiver(adapterReceiver);
		} catch (IllegalArgumentException exception) {
			reportError(readerGeneration.get(), "remove NFC adapter observer", exception);
		}
	}

	private void emitAdapterState() {
		if (godotReady && !destroyed) {
			emitAdapterState(is_enabled());
		}
	}

	private void emitAdapterState(boolean enabled) {
		if (!godotReady || destroyed) {
			return;
		}
		runOnRenderThread(() -> {
			if (godotReady && !destroyed) {
				emitSignal("adapter_state", enabled);
			}
		});
	}

	private void reportError(long generation, String operation, Exception exception) {
		String message = "Could not " + operation + ".";
		if (exception != null) {
			message += " " + exception.getClass().getSimpleName() + ": " + exception.getMessage();
			Log.e(LOG_TAG, message, exception);
		} else {
			Log.e(LOG_TAG, message);
		}
		final String detail = message;
		if (godotReady && !destroyed) {
			runOnRenderThread(() -> {
				if (godotReady && !destroyed && generation == readerGeneration.get()) {
					emitSignal("reader_error", detail);
				}
			});
		}
	}
}
