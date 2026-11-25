# frozen_string_literal: true

module CopyToProduction
  module Items
    # One item type of Copy to production. CopyToProduction::CopyService runs the shared flow (checks, lock, dependencies,
    # activity log) and asks the item type only what is specific to it.
    class BaseItem
      def initialize(sandbox:, production:)
        @sandbox = sandbox
        @production = production
      end

      def item_type
        TYPES.key(self.class.name)
      end

      # The sandbox record to copy, nil when the sandbox has none with this id.
      def find_source(id)
        sandbox.public_send(item_type.pluralize).find_by(id:)
      end

      # The kept production record with the source's code: a copy reuses it and never overwrites it.
      def find_existing(source)
        production.public_send(item_type.pluralize).find_by(code: source.code)
      end

      # The sandbox records the source references, as [item_type, record] pairs. Each one is reused when production
      # has its code, and copied along before the source otherwise.
      def dependencies(_source)
        []
      end

      # The sandbox records that belong to the source, as [item_type, record] pairs. Each one is reused when production
      # has its code, and copied along after the source otherwise.
      def children(_source)
        []
      end

      # The sandbox record the source belongs to, as an [item_type, record] pair, or nil. The copy is refused until it
      # is live.
      def parent(_source)
        nil
      end

      # The error code refusing a source that the create service would copy into something else than the sandbox holds,
      # or nil. What the create service refuses itself, the copy answers as it does.
      def refusal(_source)
        nil
      end

      # Creates the source in production through its create service, raising BaseService::FailedResult on a refusal.
      # `resolved` gives the production record of each dependency and parent, by [item_type, sandbox id].
      def copy!(_source, _resolved)
        raise NotImplementedError
      end

      # nil for an item type that is not a resource of the activity log.
      def activity_type
        "#{item_type}.copied_to_production"
      end

      private

      attr_reader :sandbox, :production

      # A product another item references, preceded by its category when the product is not reused. A product copied
      # along this way brings neither the other products of its category nor its rate cards.
      def product_dependencies(product)
        dependencies = []
        if product.product_category && !Items.build("product", sandbox:, production:).find_existing(product)
          dependencies << ["product_category", product.product_category]
        end
        dependencies << ["product", product]
      end

      # Fails the copy as a create service would, on a production record that a live item reused by code lacks.
      def not_found!(resource)
        BaseService::Result.new.not_found_failure!(resource:).raise_if_error!
      end
    end
  end
end
