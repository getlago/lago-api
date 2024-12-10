# frozen_string_literal: true

if ENV["LAGO_DATADOG_ENABLED"] == "true"

  require 'datadog/auto_instrument'
  Datadog.configure do |c|
  end

end
