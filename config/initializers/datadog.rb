# frozen_string_literal: true

if ENV["LAGO_DATADOG_ENABLED"] == "true"

  require 'datadog/auto_instrument'
  Datadog.configure do |c|
    c.agent.host = 'datadog-agent.datadog.svc.cluster.local'
    c.agent.port = 8126
  end

end
