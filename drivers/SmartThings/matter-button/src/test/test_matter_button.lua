local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button

--mock the actual device
local mock_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("button-profile.yml"),
    manufacture_info = {vendor_id = 0x0000, product_id = 0x0000},
    endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          --feature_map = 14,
          cluster_type = "SERVER"
        },
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"}
      },
    },
  },
}
)

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.PowerSource.server.attributes.BatPercentRemaining,
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.LongRelease,
  clusters.Switch.server.events.MultiPressComplete,
  clusters.Switch.server.attributes.MultiPressMax,
  clusters.Switch.server.attributes.CurrentPosition
}

local function test_init()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Handle single press sequence, no hold", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 1, {new_position = 1}  --move to position 1?
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true})) --should send initial press
  }
}
)
test.register_message_test(
  "Handle single press sequence, with hold", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 1, {new_position = 1}
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true})) --should send initial press
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.LongPress:build_test_event_report(
        mock_device, 1, {new_position = 1}
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.held({state_change = true}))
  }
}
)

test.register_message_test(
  "Handle release after short press", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 1, {new_position = 1}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 1, {previous_position = 1}
      )
    }
  },
  }
)

test.register_message_test(
  "Handle release after long press", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 1, {new_position = 1}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.LongPress:build_test_event_report(
        mock_device, 1, {new_position = 1}
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.held({state_change = true}))
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.LongRelease:build_test_event_report(
        mock_device, 1, {previous_position = 1}
      )
    }
  },
  }
)

test.register_message_test(
  "Receiving a max press attribute of 2 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 1, 2
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "held", "double"}, {visibility = {displayed = false}}))
    },
  }
)

test.register_message_test(
  "Receiving a max press attribute of 3 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 1, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "held", "double", "pushed_3x"}, {visibility = {displayed = false}}))
    },
  }
)

test.register_message_test(
  "Receiving a max press attribute of greater than 6 should not emit event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 1, 7
        )
      },
    }
  }
)

test.register_message_test(
  "Handle double press", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 1, {new_position = 1}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, 1, {new_position = 1, total_number_of_presses_counted = 2}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.double({state_change = true}))
  },

}
)

test.register_message_test(
  "Handle multi press for 4 times", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 1, {new_position = 1}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true}))
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, 1, {new_position = 1, total_number_of_presses_counted = 4}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed_4x())
  },

}
)

test.register_message_test(
  "Handle received BatPercentRemaining from device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 1, 150
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
      ),
    },
  }
)
-- run the tests
test.run_registered_tests()
