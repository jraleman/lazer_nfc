/**************************************************************************/
/*  lazer_nfc_module.mm                                                   */
/*  Registers the LazerNfc singleton for Engine.get_singleton().          */
/**************************************************************************/

#include "lazer_nfc_module.h"

#include "core/config/engine.h"
#include "core/object/object.h"

#include "lazer_nfc.h"

static LazerNfc *lazer_nfc_plugin = nullptr;

void godot_lazer_nfc_init() {
	if (lazer_nfc_plugin != nullptr) {
		return;
	}
	lazer_nfc_plugin = memnew(LazerNfc);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LazerNfc", lazer_nfc_plugin));
}

void godot_lazer_nfc_deinit() {
	if (lazer_nfc_plugin != nullptr) {
		memdelete(lazer_nfc_plugin);
		lazer_nfc_plugin = nullptr;
	}
}
