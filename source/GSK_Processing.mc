// -*- mode:java; tab-width:2; c-basic-offset:2; intent-tabs-mode:nil; -*- ex: set tabstop=2 expandtab:

// Glider's Swiss Knife (GliderSK)
// Copyright (C) 2017-2018 Cedric Dufour <http://cedric.dufour.name>
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

using Toybox.Lang;
using Toybox.Position as Pos;
using Toybox.System as Sys;

// NOTE:
//
// We use Exponential Moving Average (EMA) to smoothen the sensor values over
// the user-specified "time constant" or time period.
//
// This approach is computationally elegant since it requires no memory buffer
// and is achieved with a simple assignement:
//   Y(t) = a*X(t) + (1-a)*Y(t-1)
//
// Sticking to the canonical definition of the "time constant" (T), the
// coefficient (a) is calculated with the following formula:
//   a = 1 - exp(-1/T)
//
// The amplitude (R) of the step response at the "time constant" (T) is:
//   R = 1 - exp(T*ln(1-a))  <=>  a = 1 - exp(ln(1-R)/T)
//
// The normalized (very low-pass) cut-off (-3dB) frequency is:
//   Fc = acos(1-a²/(2*(1-a)))/(2*pi)
// For a >= sqrt(8)-2, this will fail with Fc > 0.5 (Nyquist frequency)
//
// REF:
//   https://en.wikipedia.org/wiki/Moving_average#Exponential_moving_average
//   https://dsp.stackexchange.com/questions/40462/exponential-moving-average-cut-off-frequency

class GSK_Processing {

  //
  // CONSTANTS
  //

  // Plot buffer
  public const PLOTBUFFER_SIZE = 300;  // 5 minutes = 300 seconds


  //
  // VARIABLES
  //

  // Internal calculation objects
  private var fEnergyCineticLossFactor;
  // ... we must calculate our own vertical speed
  private var iPreviousAltitudeGpoch;
  private var fPreviousAltitude;
  // ... we must calculate our own potential energy "vertical speed"
  private var iPreviousEnergyGpoch;
  private var fPreviousEnergyTotal;
  private var fPreviousEnergyCinetic;
  // ... we must calculate our own rate of turn
  private var iPreviousHeadingGpoch;
  private var fPreviousHeading;
  // ... averaging (EMA) coefficient
  private var fEmaCoefficient_present;
  private var fEmaCoefficient_past;

  // Public objects
  // ... destination values
  public var sDestinationName;
  public var oDestinationLocation;
  public var fDestinationElevation;
  // ... sensor values (fed by Toybox.Sensor)
  public var iSensorEpoch;
  //DEAD:public var fSensorAltitude;
  public var fAcceleration;
  // ... position values (fed by Toybox.Position)
  public var bPositionStateful;
  public var iPositionEpoch;
  public var iPositionGpoch;
  public var iAccuracy;
  public var oLocation;
  public var fAltitude;
  public var fGroundSpeed;
  public var fHeading;
  // ... processing
  public var bSafetyStateful;
  // ... processing values (calculated)
  public var fVariometer;
  public var fFinesse;
  public var fEnergyTotal;
  public var fEnergyCinetic;
  public var fRateOfTurn;
  public var fSpeedToDestination;
  public var fDistanceToDestination;
  public var fBearingToDestination;
  public var fAltitudeAtDestination;
  public var fHeightAtDestination;
  // ... processing status
  public var bAscent;
  public var bEstimation;
  public var bAltitudeCritical;
  public var bAltitudeWarning;
  // ... plot buffer (using integer-only operations!)
  public var iPlotIndex;
  public var aiPlotEpoch;
  public var aiPlotLatitude;
  public var aiPlotLongitude;
  public var aiPlotVariometer;


  //
  // FUNCTIONS: self
  //

  function initialize() {
    // Internal calculation objects
    self.fEnergyCineticLossFactor = 0.25f;
    // ... averaging (EMA) coefficients
    self.fEmaCoefficient_present = 1.0f;
    self.fEmaCoefficient_past = 0.0f;

    // Public objects
    // ... destination values (depending on user choice)
    self.sDestinationName = null;
    self.oDestinationLocation = null;
    self.fDestinationElevation = null;
    // ... processing values and status
    self.resetSensorData();
    self.resetPositionData();
    // ... plot buffer
    self.iPlotIndex = -1;
    self.aiPlotEpoch = new [self.PLOTBUFFER_SIZE];
    for(var i=0; i<self.PLOTBUFFER_SIZE; i++) { self.aiPlotEpoch[i] = null; }
    self.aiPlotLatitude = new [self.PLOTBUFFER_SIZE];
    for(var i=0; i<self.PLOTBUFFER_SIZE; i++) { self.aiPlotLatitude[i] = null; }
    self.aiPlotLongitude = new [self.PLOTBUFFER_SIZE];
    for(var i=0; i<self.PLOTBUFFER_SIZE; i++) { self.aiPlotLongitude[i] = null; }
    self.aiPlotVariometer = new [self.PLOTBUFFER_SIZE];
    for(var i=0; i<self.PLOTBUFFER_SIZE; i++) { self.aiPlotVariometer[i] = null; }
  }

  function resetSensorData() {
    //Sys.println("DEBUG: GSK_Processing.resetSensorData()");

    // Reset
    // ... sensor values
    self.iSensorEpoch = null;
    //DEAD:self.fSensorAltitude = null;
    self.fAcceleration = null;
  }

  function resetPositionData() {
    //Sys.println("DEBUG: GSK_Processing.resetPositionData()");

    // Reset
    // ... position values
    self.bPositionStateful = false;
    self.iPositionEpoch = null;
    self.iPositionGpoch = null;
    self.iAccuracy = Pos.QUALITY_NOT_AVAILABLE;
    self.oLocation = null;
    self.fAltitude = null;
    self.fGroundSpeed = null;
    self.fHeading = null;
    // ... we must calculate our own vertical speed
    self.iPreviousAltitudeGpoch = null;
    self.fPreviousAltitude = 0.0f;
    // ... we must calculate our own potential energy "vertical speed"
    self.iPreviousEnergyGpoch = null;
    self.fPreviousEnergyTotal = 0.0f;
    self.fPreviousEnergyCinetic = 0.0f;
    // ... we must calculate our own rate of turn
    self.iPreviousHeadingGpoch = null;
    self.fPreviousHeading = 0.0f;
    // ... processing
    self.bSafetyStateful = false;
    // ... processing values (calculated)
    self.fVariometer = null;
    self.fFinesse = null;
    self.fEnergyTotal = null;
    self.fEnergyCinetic = null;
    self.fRateOfTurn = null;
    self.fSpeedToDestination = null;
    self.fDistanceToDestination = null;
    self.fBearingToDestination = null;
    self.fAltitudeAtDestination = null;
    self.fHeightAtDestination = null;
    // ... processing status
    self.bAscent = true;
    self.bEstimation = true;
    self.bAltitudeCritical = false;
    self.bAltitudeWarning = false;
  }

  function importSettings() {
    // Time constant
    if($.GSK_oSettings.iGeneralTimeConstant) {
      self.fEmaCoefficient_past = Math.pow(Math.E, -1.0f/$.GSK_oSettings.iGeneralTimeConstant);
    }
    else {
      self.fEmaCoefficient_past = 0.0f;
    }
    self.fEmaCoefficient_present = 1.0f - self.fEmaCoefficient_past;
    //Sys.println(Lang.format("DEBUG: EMA coefficient = $1$", [self.fEmaCoefficient_present]));

    // Energy compensation
    self.fEnergyCineticLossFactor = 1.0f - $.GSK_oSettings.fVariometerEnergyEfficiency;
  }

  function setDestination(_sName, _oLocation, _fElevation) {
    self.sDestinationName = _sName;
    self.oDestinationLocation = _oLocation;
    self.fDestinationElevation = _fElevation;
  }

  function processSensorInfo(_oInfo, _iEpoch) {
    //Sys.println("DEBUG: GSK_Processing.processSensorInfo()");

    // Process sensor data
    var fValue;

    //DEAD:// ... altitude
    //DEAD:if(_oInfo has :altitude and _oInfo.altitude != null) {
    //DEAD:  if(self.fSensorAltitude == null) {
    //DEAD:    self.fSensorAltitude = _oInfo.altitude;
    //DEAD:  }
    //DEAD:  else {
    //DEAD:    self.fSensorAltitude = self.fEmaCoefficient_present * _oInfo.altitude + self.fEmaCoefficient_past * self.fSensorAltitude;
    //DEAD:  }
    //DEAD:  //Sys.println(Lang.format("DEBUG: (Sensor.Info) altitude = $1$", [self.fSensorAltitude]));
    //DEAD:}
    //DEAD://else {
    //DEAD://  Sys.println("WARNING: Sensor data have no altitude information (:altitude)");
    //DEAD://}

    // ... acceleration
    if(_oInfo has :accel and _oInfo.accel != null) {
      fValue = Math.sqrt(_oInfo.accel[0]*_oInfo.accel[0]+_oInfo.accel[1]*_oInfo.accel[1]+_oInfo.accel[2]*_oInfo.accel[2])/1000.0f;
      if(self.fAcceleration == null) {
        self.fAcceleration = fValue;
      }
      else {
        self.fAcceleration = self.fEmaCoefficient_present * fValue + self.fEmaCoefficient_past * self.fAcceleration;
      }
      //Sys.println(Lang.format("DEBUG: (Sensor.Info) acceleration = $1$", [self.fAcceleration]));
    }
    //else {
    //  Sys.println("WARNING: Sensor data have no acceleration information (:accel)");
    //}

    // Done
    self.iSensorEpoch = _iEpoch;
  }

  function processPositionInfo(_oInfo, _iEpoch) {
    //Sys.println("DEBUG: GSK_Processing.processPositionInfo()");

    // Process position data
    var fValue;
    var bStateful = true;

    // ... accuracy
    if(_oInfo has :accuracy and _oInfo.accuracy != null) {
      self.iAccuracy = _oInfo.accuracy;
      //Sys.println(Lang.format("DEBUG: (Position.Info) accuracy = $1$", [self.iAccuracy]));
    }
    else {
      //Sys.println("WARNING: Position data have no accuracy information (:accuracy)");
      self.iAccuracy = Pos.QUALITY_NOT_AVAILABLE;
      return;
    }
    if(self.iAccuracy == Pos.QUALITY_NOT_AVAILABLE or (self.iAccuracy == Pos.QUALITY_LAST_KNOWN and self.iPositionEpoch == null)) {
      //Sys.println("WARNING: Position accuracy is not good enough to continue or start processing");
      self.iAccuracy = Pos.QUALITY_NOT_AVAILABLE;
      return;
    }

    // ... timestamp
    // WARNING: the value of the position (GPS) timestamp is NOT the UTC epoch but the GPS timestamp (NOT translated to the proper year quadrant... BUG?)
    //          https://en.wikipedia.org/wiki/Global_Positioning_System#Timekeeping
    if(_oInfo has :when and _oInfo.when != null) {
      self.iPositionGpoch = _oInfo.when.value();
      //DEVEL:self.iPositionGpoch = _iEpoch;  // SDK 3.0.x BUG!!! (:when remains constant)
      //Sys.println(Lang.format("DEBUG: (Position.Info) when = $1$", [self.self.iPositionGpoch]));
    }
    else {
      //Sys.println("WARNING: Position data have no timestamp information (:when)");
      self.iAccuracy = Pos.QUALITY_NOT_AVAILABLE;
      return;
    }

    // ... position
    self.bPositionStateful = false;
    if(_oInfo has :position and _oInfo.position != null) {
      self.oLocation = _oInfo.position;
      //Sys.println(Lang.format("DEBUG: (Position.Info) position = $1$, $2$", [self.oLocation.toDegrees()[0], self.oLocation.toDegrees()[1]]));
      // ... distance/bearing to destination
      if(self.oDestinationLocation != null) {
        var adPositionRadians = self.oLocation.toRadians();
        var adDestinationRadians = self.oDestinationLocation.toRadians();
        self.fDistanceToDestination = LangUtils.distance(adPositionRadians, adDestinationRadians);
        self.fBearingToDestination = LangUtils.bearing(adPositionRadians, adDestinationRadians);
        //Sys.println(Lang.format("DEBUG: (Calculated) distance/bearing to destination = $1$ / $2$", [self.fDistanceToDestination, self.fBearingToDestination * 57.2957795131f]));
      }
      else {
        //Sys.println("ERROR: No destination data");
        self.fDistanceToDestination = null;
        self.fBearingToDestination = null;
      }
    }
    //else {
    //  Sys.println("WARNING: Position data have no position information (:position)");
    //}
    if(self.oLocation == null) {
      bStateful = false;
    }

    // ... altitude
    if($.GSK_oAltimeter.fAltitudeActual != null) {  // ... the closest to the device's raw barometric sensor value
      self.fAltitude = $.GSK_oAltimeter.fAltitudeActual;
    }
    //DEAD:else if(self.fSensorAltitude != null) {  // ... sometimes flats-out (for several seconds/minutes)
    //DEAD:  self.fAltitude = self.fSensorAltitude;
    //DEAD:}
    //DEAD:else if(_oInfo has :altitude and _oInfo.altitude != null) {  // ... GPS altitude? sucks!
    //DEAD:  if(self.fAltitude == null) {
    //DEAD:    self.fAltitude = _oInfo.altitude;
    //DEAD:  }
    //DEAD:  else {
    //DEAD:    self.fAltitude = self.fEmaCoefficient_present * _oInfo.altitude + self.fEmaCoefficient_past * self.fAltitude;
    //DEAD:  }
    //DEAD:  //Sys.println(Lang.format("DEBUG: (Position.Info) altitude = $1$", [self.fAltitude]));
    //DEAD:}
    //else {
    //  Sys.println("WARNING: Position data have no altitude information (:altitude)");
    //}
    if(self.fAltitude == null) {
      bStateful = false;
    }

    // ... ground speed
    if(_oInfo has :speed and _oInfo.speed != null) {
      if(self.fGroundSpeed == null) {
        self.fGroundSpeed = _oInfo.speed;
      }
      else {
        self.fGroundSpeed = self.fEmaCoefficient_present * _oInfo.speed + self.fEmaCoefficient_past * self.fGroundSpeed;
      }
      //Sys.println(Lang.format("DEBUG: (Position.Info) ground speed = $1$", [self.fGroundSpeed]));
    }
    //else {
    //  Sys.println("WARNING: Position data have no speed information (:speed)");
    //}
    if(self.fGroundSpeed == null) {
      bStateful = false;
    }

    // ... variometer
    if($.GSK_oSettings.iVariometerMode == 0 and self.fAltitude != null) {  // ... altimetric variometer
      if(self.iPreviousAltitudeGpoch != null and self.iPositionGpoch-self.iPreviousAltitudeGpoch != 0) {
        self.fVariometer = (self.fAltitude-self.fPreviousAltitude) / (self.iPositionGpoch-self.iPreviousAltitudeGpoch);
        //Sys.println(Lang.format("DEBUG: (Calculated) altimetric variometer = $1$", [self.fVariometer]));
      }
      self.iPreviousAltitudeGpoch = self.iPositionGpoch;
      self.fPreviousAltitude = self.fAltitude;
      self.iPreviousEnergyGpoch = null;  // ... prevent artefact when switching variometer mode
    }
    else if($.GSK_oSettings.iVariometerMode == 1 and self.fAltitude != null and self.fGroundSpeed != null) {  // ... energetic variometer
      self.fEnergyCinetic = 0.5f*self.fGroundSpeed*self.fGroundSpeed;
      self.fEnergyTotal = self.fEnergyCinetic + 9.80665f*self.fAltitude;
      //Sys.println(Lang.format("DEBUG: (Calculated) total energy = $1$", [self.fEnergyTotal]));
      if(self.iPreviousEnergyGpoch != null and self.iPositionGpoch-self.iPreviousEnergyGpoch != 0) {
        self.fVariometer = (self.fEnergyTotal-self.fPreviousEnergyTotal-self.fEnergyCineticLossFactor*(self.fEnergyCinetic-self.fPreviousEnergyCinetic)) / (self.iPositionGpoch-self.iPreviousEnergyGpoch) * 0.1019716213f;  // ... 1.0f / 9.80665f = 1.019716213f
        //Sys.println(Lang.format("DEBUG: (Calculated) energetic variometer = $1$", [self.fVariometer]));
      }
      self.iPreviousEnergyGpoch = self.iPositionGpoch;
      self.fPreviousEnergyTotal = self.fEnergyTotal;
      self.fPreviousEnergyCinetic = self.fEnergyCinetic;
      self.iPreviousAltitudeGpoch = null;  // ... prevent artefact when switching variometer mode
    }
    if(self.fVariometer == null) {
      bStateful = false;
    }

    // ... heading
    // NOTE: we consider heading meaningful only if ground speed is above 1.0 m/s
    if(self.fGroundSpeed != null and self.fGroundSpeed >= 1.0f and _oInfo has :heading and _oInfo.heading != null) {
      // WARNING: _oInfo.heading (in radians) may return negative values (at least in the simulator)
      var fHeading_normalized;
      fHeading_normalized = _oInfo.heading;
      if(fHeading_normalized < 0.0f) {
        fHeading_normalized += 6.28318530718f;
      }
      if(self.fHeading == null) {
        self.fHeading = fHeading_normalized;
      }
      else if(self.fHeading > 4.71238898039f and fHeading_normalized < 1.5707963268f) {  // ... NW to NE discontinuity
        self.fHeading = self.fEmaCoefficient_present * (fHeading_normalized + 6.28318530718f) + self.fEmaCoefficient_past * self.fHeading;
        if(self.fHeading >= 6.28318530718f) {
          self.fHeading -= 6.28318530718f;
        }
      }
      else if(self.fHeading < 1.5707963268f and fHeading_normalized > 4.71238898039f) {  // ... NE to NW discontinuity
        self.fHeading = self.fEmaCoefficient_present * (fHeading_normalized - 6.28318530718f) + self.fEmaCoefficient_past * self.fHeading;
        if(self.fHeading < 0.0f) {
          self.fHeading += 6.28318530718f;
        }
      }
      else {
        self.fHeading = self.fEmaCoefficient_present * fHeading_normalized + self.fEmaCoefficient_past * self.fHeading;
      }
      //Sys.println(Lang.format("DEBUG: (Position.Info) heading = $1$°", [self.fHeading * 57.2957795131f]));
      // ... rate of turn
      if(self.iPreviousHeadingGpoch != null and self.iPositionGpoch-self.iPreviousHeadingGpoch != 0) {
        fValue = (self.fHeading-self.fPreviousHeading) / (self.iPositionGpoch-self.iPreviousHeadingGpoch);
        if(fValue < -3.14159265359f) {
          fValue += 6.28318530718f;
        }
        else if(fValue > 3.14159265359f) {
          fValue -= 6.28318530718f;
        }
        self.fRateOfTurn = fValue;
        //Sys.println(Lang.format("DEBUG: (Calculated) rate of turn = $1$°", [self.fRateOfTurn * 57.2957795131f]));
      }
      self.iPreviousHeadingGpoch = self.iPositionGpoch;
      self.fPreviousHeading = self.fHeading;
      // ... speed-to(wards)-destination
      if(self.fBearingToDestination != null) {
        self.fSpeedToDestination = self.fGroundSpeed * Math.cos(self.fHeading-self.fBearingToDestination);
        //Sys.println(Lang.format("DEBUG: (Calculated) speed-to(wards)-destination = $1$", [self.fSpeedToDestination]));
      }
      else {
        self.fSpeedToDestination = null;
      }
    }
    else {
      //Sys.println("WARNING: Position data have no (meaningful) heading information (:heading)");
      self.fHeading = null;
      self.iPreviousHeadingGpoch = null;
      self.fRateOfTurn = null;
      self.fSpeedToDestination = null;
    }
    // NOTE: heading and rate-of-turn data are not required for processing finalization

    // Finalize
    if(bStateful) {
      self.bPositionStateful = true;
      if(self.iAccuracy > Pos.QUALITY_LAST_KNOWN) {
        self.iPositionEpoch = _iEpoch;

        // Plot buffer
        self.iPlotIndex = (self.iPlotIndex+1) % self.PLOTBUFFER_SIZE;
        self.aiPlotEpoch[self.iPlotIndex] = self.iPositionEpoch;
        // ... location as (integer) milliseconds of arc
        var adPositionDegrees = self.oLocation.toDegrees();
        self.aiPlotLatitude[self.iPlotIndex] = (adPositionDegrees[0]*3600000.0f).toNumber();
        self.aiPlotLongitude[self.iPlotIndex] = (adPositionDegrees[1]*3600000.0f).toNumber();
        // ... vertical speed as (integer) millimeter-per-second
        self.aiPlotVariometer[self.iPlotIndex] = (self.fVariometer*1000.0f).toNumber();
      }
    }

    // ... safety
    self.processSafety();
  }

  function processSafety() {
    //Sys.println("DEBUG: GSK_Processing.processSafety()");
    self.bSafetyStateful = false;
    if(!self.bPositionStateful or self.fDestinationElevation == null or self.fDistanceToDestination == null or self.fSpeedToDestination == null) {
      //Sys.println("ERROR: Incomplete data; cannot proceed");
      self.bAscent = false;
      self.fFinesse = null;
      self.bEstimation = true;
      self.fAltitudeAtDestination = null;
      self.fHeightAtDestination = null;
      self.bAltitudeCritical = false;
      self.bAltitudeWarning = false;
      return;
    }

    // Ascent/finesse
    // ... ascending ?
    if(self.fVariometer >= -0.005f * self.fGroundSpeed) {  // climbing (quite... finesse >= 200)
      self.bAscent = true;
    }
    else {  // descending (really!)
      self.bAscent = false;
    }
    //Sys.println(Lang.format("DEBUG: (Calculated) ascent = $1$", [self.bAscent]));

    // ... finesse
    if(self.bAscent) {
      // ALGO: let's use the user-specified reference finesse to estimate where we'd stand if we were to descend and head straight back home
      self.fFinesse = $.GSK_oSettings.iSafetyFinesse.toFloat();
    }
    else {
      self.fFinesse = - self.fGroundSpeed / self.fVariometer;
    }
    //Sys.println(Lang.format("DEBUG: (Calculated) average finesse = $1$", [self.fFinesse]));

    // Safety
    // ALGO: The trick here is to avoid alerts when our altitude is high enough, no matter what our descent rate (finesse) or heading are
    //       (we ARE enjoying ourself gliding in that blue-blue sky; that's what we want in the first place!).
    //       BUT, if the altitude becomes to low (height at destination below or equal to our decision height), then we must trigger
    //       meaningful alerts.
    if(self.fFinesse > 0.0f) {
      // ALGO: Let's start by estimating our altitude at destination assuming we're heading straight to it - i.e. speed-to(wards)-destination
      //       is equal to ground speed - and using the lowest between our reference finesse and actual finesse.
      //       This is the worst-case scenario as far as finesse is concerned BUT the best-case scenario as far as our heading
      //       (vs. bearing to destination) is concerned.
      self.fAltitudeAtDestination = self.fAltitude - self.fDistanceToDestination / (self.fFinesse < $.GSK_oSettings.iSafetyFinesse ? self.fFinesse : $.GSK_oSettings.iSafetyFinesse);
      self.fHeightAtDestination = self.fAltitudeAtDestination-self.fDestinationElevation;
      // ALGO: Then, if the corresponding height at destination is below our decision height, let's re-calculate our altitude at
      //       destination by using our *actual* finesse (unless we're ascending) and our *actual* speed-to(wards)-destination
      //       (which accounts for our heading vs bearing to destination).
      //       No more worst-case/best-case scenario now; we're using only *actual*, meaningful values!
      if(self.fHeightAtDestination <= $.GSK_oSettings.fSafetyHeightDecision) {
        self.bEstimation = false;
        if(self.fSpeedToDestination > 0.0f) {
          self.fAltitudeAtDestination = self.fAltitude - self.fDistanceToDestination / self.fFinesse * self.fGroundSpeed / self.fSpeedToDestination;
          self.fHeightAtDestination = self.fAltitudeAtDestination-self.fDestinationElevation;
          // ALGO: Our finesse or speed-to(wards)-destination aren't good enough; we'll touch the ground before reaching our destination
          if(self.fHeightAtDestination <= 0.0f) {
            self.fAltitudeAtDestination = self.fDestinationElevation;
            self.fHeightAtDestination = 0.0f;
          }
        }
        else {
          // ALGO: We're moving away from our destination; we'll touch the ground before ever reaching our destination
          self.fAltitudeAtDestination = self.fDestinationElevation;
          self.fHeightAtDestination = 0.0f;
        }
      }
      else {
        self.bEstimation = true;
      }
    }
    else {
      // ALGO: We're not moving; we'll touch the ground before reaching our destination
      self.bEstimation = false;
      self.fAltitudeAtDestination = self.fDestinationElevation;
      self.fHeightAtDestination = 0.0f;
    }
    //Sys.println(Lang.format("DEBUG: (Calculated) altitude/height at destination = $1$ / $2$", [self.fAltitudeAtDestination, self.fHeightAtDestination]));

    // ... status
    self.bAltitudeCritical = false;
    self.bAltitudeWarning = false;
    if(self.fHeightAtDestination <= $.GSK_oSettings.fSafetyHeightCritical) {
      self.bAltitudeCritical = true;
    }
    else if(self.fHeightAtDestination <= $.GSK_oSettings.fSafetyHeightWarning) {
      self.bAltitudeWarning = true;
    }

    // Done
    self.bSafetyStateful = true;
  }

}