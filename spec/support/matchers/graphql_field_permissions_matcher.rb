# frozen_string_literal: true

# Usage:
#  it { is_expected.to have_a_field(:api_key).with_permissions('developers:manage') }
#
module RSpec
  module GraphqlMatchers
    class HaveAField < BaseMatcher
      def with_permissions(expected_permissions)
        @expectations << HaveAFieldMatchers::WithPermissions.new(expected_permissions)
        self
      end
      alias with_permission with_permissions
    end

    module HaveAFieldMatchers
      class WithPermissions
        def initialize(expected_permissions)
          @expected_permissions = Array.wrap(expected_permissions)
        end

        def description
          "with permissions `#{@expected_permissions}`"
        end

        def matches?(actual_field)
          @actual_permissions = actual_field.permissions
          @actual_permissions.sort == @expected_permissions.sort
        end

        def failure_message
          "#{description}, but it was `#{@actual_permissions}`"
        end
      end
    end
  end
end
