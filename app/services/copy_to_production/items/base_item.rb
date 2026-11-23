# frozen_string_literal: true

module CopyToProduction
  module Items
    # One item type of Copy to production. CopyToProduction::CopyService and CopyToProduction::PreviewService run the shared flow
    # (checks, lock, dependencies, activity log) and ask the item type only what is specific to it.
    class BaseItem
      def initialize(sandbox:, production:)
        @sandbox = sandbox
        @production = production
      end

      def item_type
        TYPES.key(self.class.name)
      end

      # The sandbox record to copy, nil when the sandbox has none with this id.
      def find_source(_id)
        raise NotImplementedError
      end

      # The kept production record with the source's code: a copy reuses it and never overwrites it.
      def find_existing(_source)
        raise NotImplementedError
      end

      # The sandbox records the source references, as [item_type, record] pairs. Each one is reused when production
      # has its code, and copied along before the source otherwise.
      def dependencies(_source)
        []
      end

      # The sandbox record the source belongs to, as an [item_type, record] pair, or nil. The copy is refused until it
      # is live.
      def parent(_source)
        nil
      end

      # The error code refusing a source that the create service would refuse, or that cannot be copied, so that the
      # preview and the copy agree. Nil when it can be moved.
      def refusal(_source)
        nil
      end

      # Creates the source in production through its create service and returns the record. Raises
      # BaseService::FailedResult on a refusal, so that the whole move rolls back. `resolved` gives the production
      # record of each dependency and parent, by [item_type, sandbox id].
      def copy!(_source, _resolved)
        raise NotImplementedError
      end

      # Unique indexes a concurrent write can hit, by name, with the field they answer on.
      def unique_indexes
        {}
      end

      def activity_type
        "#{item_type}.copied_to_production"
      end

      private

      attr_reader :sandbox, :production
    end
  end
end
