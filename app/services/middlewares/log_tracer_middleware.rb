# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Middlewares
  class LogTracerMiddleware < BaseMiddleware
    def call(&block)
      LagoTracer.in_span("#{service_instance.class.name}#call") do
        call_next(&block)
      end
    end
  end
end
