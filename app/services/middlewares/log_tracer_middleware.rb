# frozen_string_literal: true

module Middlewares
  class LogTracerMiddleware < BaseMiddleware
    def call
      LagoTracer.in_span("#{service_instance.class.name}#call") do
        super
      end
    end
  end
end
