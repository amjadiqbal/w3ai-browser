/* -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "updaterfileutils_osx.h"

#include <Cocoa/Cocoa.h>

bool IsRecursivelyWritable(const char* aPath) {
  // TMRW Browser is distributed as a user-installed DMG. The app always lives
  // in the user's own /Applications (or ~/Applications) and is therefore always
  // writable by that user. Returning true unconditionally avoids triggering the
  // macOS XPC-elevated update path, which requires a registered privileged
  // helper daemon that we do not ship.
  return true;
}
