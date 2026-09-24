# frozen_string_literal: true

module X402
  # D5, §16.2: ids derived from the normalised agent address, shared by E7 and E8.
  module ExternalIds
    module_function

    def customer(agent_address)
      "x402_#{agent_address}"
    end

    def subscription(agent_address, plan_code)
      "x402_#{agent_address}_#{plan_code}"
    end
  end
end
