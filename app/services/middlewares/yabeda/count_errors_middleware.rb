# frozen_string_literal: true

module Middlewares
  module Yabeda
    class CountErrorsMiddleware < BaseMiddleware
      # Registers a counter metric for operation errors.
      def self.on_use(operation:)
        ::Yabeda.configure do
          group :lago do
            counter :"#{operation}_errors",
              tags: %i[error_class],
              comment: "Errors of #{operation}"
          end
        end
      end

      def after_call(result)
        return if result.success?

        operation = service_instance.class.name.underscore.tr("/", "_")
        error_class = result.error.class.name.demodulize.underscore
        ::Yabeda.lago.public_send(:"#{operation}_errors").increment({error_class:})
      end
    end
  end
end
