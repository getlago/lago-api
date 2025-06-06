# frozen_string_literal: true

require "current_context"

ActiveJob::Traceable.tracing_info_getter = lambda do
  {
    membership: CurrentContext.membership,
    source: CurrentContext.source
  }
end

ActiveJob::Traceable.tracing_info_setter = lambda do |attributes|
  attributes ||= {}

  CurrentContext.membership = attributes[:membership]
  CurrentContext.source = attributes[:source]
end
