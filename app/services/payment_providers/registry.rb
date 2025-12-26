# frozen_string_literal: true

module PaymentProviders
  # This class implements a registry pattern to manage payment providers services.
  # Services are registered within the PaymentProviders::XXProvider classes using the register_services method.
  # The current implementation allows a lazy loading of the providers
  class Registry
    ACTIONS = %i[create_customer manage_customer create_payment manage_invoice_payment manage_payment_request_payment].freeze

    # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    class_attribute :providers, instance_writer: false, default: {}
    # rubocop:enable ThreadSafety/ClassAndModuleAttributes

    # Register a new payment provider with the given services.
    # If the provider is already registered, an error is raised by default.
    #
    # The on_conflict option can be set:
    #  - :ignore to avoid raising an error
    #  - :replace to replace the existing services
    #  - :merge to merge the existing services with the new ones
    #  - :raise to raise an error (default)
    #
    # The list of accepted actions is defined by the ACTIONS constant.
    def self.register(provider, services, on_conflict: :raise)
      raise ArgumentError, "Invalid actions" unless valid_actions?(services.keys)

      existing_service = providers[provider.to_sym]

      unless existing_service
        providers[provider.to_sym] = services
        return
      end

      case on_conflict.to_sym
      when :raise
        raise ArgumentError, "#{provider} already registered"
      when :replace
        providers[provider.to_sym] = services
      when :merge
        providers[provider.to_sym].merge!(services)
      when :ignore
        # Do nothing
      end
    end

    def self.valid_actions?(actions)
      actions.all? { ACTIONS.include?(it) }
    end

    def self.new_instance(provider, action, *args, **kwargs)
      ensure_providers_loaded(provider)

      registered_provider = providers[provider.to_sym]
      raise NotImplementedError unless registered_provider

      service_class = registered_provider[action.to_sym]
      raise NotImplementedError unless service_class

      service_class.constantize.new(*args, **kwargs)
    end

    # Ensure all provider models are loaded before accessing the registry
    def self.ensure_providers_loaded(provider)
      return if providers.key?(provider.to_sym)

      require Rails.root.join("app/models/payment_providers/#{provider}_provider.rb")
    rescue LoadError
      raise NotImplementedError
    end
  end
end
