# frozen_string_literal: true

require "yabeda"

Yabeda.configure do
    default_tag :service, "lago-api"
    default_tag :environment, Rails.env
    default_tag :version, ENV["LAGO_VERSION"] || "unknown"
end
