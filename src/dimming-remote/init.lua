-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local utils = require "st.utils"
local log = require "log"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local button_utils = require "button_utils"

local ZIBEE_DIMMING_SWITCH_FINGERPRINTS = {
  { mfr = "OSRAM", model = "LIGHTIFY Dimming Switch" },
  { mfr = "CentraLite", model = "3130" },
  { mfr = "Philips", model = "ROM001" }
}

local function can_handle_zigbee_dimming_remote(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZIBEE_DIMMING_SWITCH_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function button_pushed_handler(button_number)
  return function(self, device, value, zb_rx)
    button_utils.init_button_press(device, button_number)
  end
end

local function button_released_handler(self, device, value, zb_rx)
  button_utils.send_pushed_or_held_button_event_if_applicable(device, 1)
  button_utils.send_pushed_or_held_button_event_if_applicable(device, 2)
end

local function added_handler(self, device)
  for _, component in pairs(device.profile.components) do
    --local number_of_buttons = component.id == "main" and 3 or 1

    device:emit_component_event(component, capabilities.button.supportedButtonValues({"down", "up", "down_hold", "up_hold"}))
    --device:emi_component_event(component, capabilities.button.numberOfButtons({value = number_of_buttons}))
    --device:emi_component_event(component, capabilities.button.numberOfButtons({value = 1}))
  end

  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
end

local function do_configure(self, device)
  --device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 1, 1, 1))
  --device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))

  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
end

local battery_percent_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))

  --local tmp = table.concat(value)..""
  log.debug("Value: "..value.value)

  --tmp = table.concat(rb_rx)..""
  --log.debug("ZB_RX: "..tmp)

  --local batteryPercent = math.floor(value.value / 200 * 100 + 0.5);
  --device:emit_event(capabilities.battery.battery(batteryPercent))
end

local function init(self,device)
   battery_defaults.build_linear_voltage_init(2.1, 3.0)
end

local dimming_remote = {
  NAME = "Dimming Remote",
  lifecycle_handlers = {
    init = init,
    added = added_handler,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.Step.ID] = button_utils.buttonHeldHandler,
        [Level.server.commands.Stop.ID] = button_utils.buttonStopHandler
      },
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID]           = button_utils.buttonOffHandler,
        [OnOff.server.commands.OffWithEffect.ID] = button_utils.buttonOffHandler,
        [OnOff.server.commands.On.ID]            = button_utils.buttonOnHandler
      }
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percent_handler
      }
    }
  },
  can_handle = can_handle_zigbee_dimming_remote
}

return dimming_remote
