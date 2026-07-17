# frozen_string_literal: true

# TEMPORARY bridge for legacy multi-method services not yet migrated to the single
# `call` + typed `Result` pattern.
#
# Include the concern and declare a `RESULTS` constant mapping each public
# method to the typed Result it should return:
#
#   class Auth::GoogleService < BaseService
#     include TypedResults
#
#     RESULTS = {
#       authorize_url: BaseResult[:url],
#       login: BaseResult[:user, :token],
#       register_user: BaseResult[:user, :organization, :membership, :token],
#       accept_invite: Invites::AcceptService::Result
#     }.freeze
#
#     private
#
#     def login(code) = ...
#   end
#
# The target methods should be declared `private` to discourage direct
# invocation; `call` reaches them via `send`, so routing still works.
#
# The class-level `call` returns a typed Result instead of the
# deprecated LegacyResult (OpenStruct):
#
#   Auth::GoogleService.call(:login, code)
#   Auth::GoogleService.call(:register_user, code, organization_name)
#
# The service is built without constructor arguments; all arguments are
# forwarded to the target method.
module TypedResults
  extend ActiveSupport::Concern

  class_methods do
    def call(method_name, *args, **kwargs, &block)
      result_class = self::RESULTS.fetch(method_name) do
        raise ArgumentError, "#{name}: #{method_name.inspect} is not declared in RESULTS"
      end

      instance = new
      instance.send(:result=, result_class.new)
      instance.send(:with_middlewares) do
        instance.send(method_name, *args, **kwargs, &block)
      end
    end

    def call!(method_name, *args, **kwargs, &block)
      call(method_name, *args, **kwargs, &block).raise_if_error!
    end
  end
end
