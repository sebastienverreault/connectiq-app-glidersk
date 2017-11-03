// -*- mode:java; tab-width:2; c-basic-offset:2; intent-tabs-mode:nil; -*- ex: set tabstop=2 expandtab:

// Glider's Swiss Knife (GliderSK)
// Copyright (C) 2017 Cedric Dufour <http://cedric.dufour.name>
//
// Glider's Swiss Knife (GliderSK) is free software:
// you can redistribute it and/or modify it under the terms of the GNU General
// Public License as published by the Free Software Foundation, Version 3.
//
// Glider's Swiss Knife (GliderSK) is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the GNU General Public License for more details.
//
// SPDX-License-Identifier: GPL-3.0
// License-Filename: LICENSE/GPL-3.0.txt

using Toybox.System as Sys;
using Toybox.WatchUi as Ui;

// Menu: resources/menus/menuSettingsUnits.xml

class MenuDelegateSettingsUnits extends Ui.MenuInputDelegate {

  //
  // FUNCTIONS: Ui.MenuInputDelegate (override/implement)
  //

  function initialize() {
    MenuInputDelegate.initialize();
  }

  function onMenuItem(item) {
    if (item == :menuUnitDistance) {
      //Sys.println("DEBUG: MenuDelegateSettingsUnits.onMenuItem(:menuUnitDistance)");
      Ui.pushView(new PickerUnitDistance(), new PickerDelegateUnitDistance(), Ui.SLIDE_IMMEDIATE);
    }
    else if (item == :menuUnitElevation) {
      //Sys.println("DEBUG: MenuDelegateSettingsUnits.onMenuItem(:menuUnitElevation)");
      Ui.pushView(new PickerUnitElevation(), new PickerDelegateUnitElevation(), Ui.SLIDE_IMMEDIATE);
    }
    else if (item == :menuUnitRateOfTurn) {
      //Sys.println("DEBUG: MenuDelegateSettingsUnits.onMenuItem(:menuUnitRateOfTurn)");
      Ui.pushView(new PickerUnitRateOfTurn(), new PickerDelegateUnitRateOfTurn(), Ui.SLIDE_IMMEDIATE);
    }
    else if (item == :menuTimeUTC) {
      //Sys.println("DEBUG: MenuDelegateSettingsUnits.onMenuItem(:menuTimeUTC)");
      Ui.pushView(new PickerTimeUTC(), new PickerDelegateTimeUTC(), Ui.SLIDE_IMMEDIATE);
    }
  }

}
