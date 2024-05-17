# frozen_string_literal: true

require 'current_context'

ActiveJob::Traceable.tracing_info_getter = lambda do
  {
    membership: CurrentContext.membership
  }
end

ActiveJob::Traceable.tracing_info_setter = lambda do |attributes|
  return unless attributes

  CurrentContext.membership = attributes[:membership]
end
