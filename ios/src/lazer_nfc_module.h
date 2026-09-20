/**************************************************************************/
/*  lazer_nfc_module.h                                                    */
/*  Entry points named by lazer_nfc.gdip.                                 */
/**************************************************************************/

#ifndef LAZER_NFC_MODULE_H
#define LAZER_NFC_MODULE_H

// Godot writes `extern void godot_lazer_nfc_init();` into the generated
// godot_apple_embedded/dummy.cpp, so these keep C++ linkage on purpose.
// Declaring them `extern "C"` would leave the generated file unlinkable.
void godot_lazer_nfc_init();
void godot_lazer_nfc_deinit();

#endif // LAZER_NFC_MODULE_H
