# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::BaseService, type: :service do
  subject(:service) { described_class.new }

  it { is_expected.to be_kind_of(AfterCommitEverywhere) }
  it { is_expected.to respond_to(:call) }
  it { is_expected.to respond_to(:call_async) }
  it { is_expected.to respond_to(:call_with_activity_log) }

  context "with current_user" do
    it "assigns the current_user to the result" do
      result = described_class.new.send :result

      expect(result).to be_a(::BaseService::Result)
    end

    it "does not assign the current_user to the result if it isn't a User" do
      result = described_class.new([]).send :result

      expect(result.user).to be_nil
    end
  end

  context "with activity_loggable" do
    let(:service_class) do
      action = activity_loggable_action
      after_commit = activity_loggable_after_commit
      Class.new(described_class) do
        const_set(:Result, BaseResult[:subscription])

        activity_loggable(action: action, record: -> { subscription }, after_commit:)

        def initialize(subscription:)
          @subscription = subscription
          super()
        end

        def call
          subscription.update!(name: "Updated Subscription")

          result.subscription = subscription
          result
        end

        private

        attr_reader :subscription
      end
    end

    let(:subscription) { create(:subscription, name: "My Subscription") }
    let(:activity_loggable_after_commit) { false }

    def test_service_with_activity_loggable(after_commit:, action_match_updated: false)
      allow(Utils::ActivityLog).to receive(:produce).and_wrap_original do |m, *args, **kwargs, &block|
        if action_match_updated
          # For "updated" actions, `Utils::ActivityLog#produce` will execute `BaseService#call` method so subscription is not yet updated here
          expect(subscription.name).to eq("My Subscription")
        else
          # For other actions, `Utils::ActivityLog#produce` is executed after `BaseService#call` method so subscription is already updated here
          expect(subscription.name).to eq("Updated Subscription")
        end

        result = m.call(*args, **kwargs, &block)

        # Test that `Utils::ActivityLog#produce` returns the result of the service call
        expect(result).to be_success
        expect(result.subscription).to eq(subscription)
        expect(result.subscription.name).to eq("Updated Subscription")

        result
      end

      result = service_class.call(subscription:)

      expect(Utils::ActivityLog).to have_received(:produce).with(subscription, activity_loggable_action, after_commit:)

      expect(result).to be_success
      expect(result.subscription).to eq(subscription)
      expect(result.subscription.name).to eq("Updated Subscription")
    end

    context "when action matches /updated/" do
      let(:activity_loggable_action) { "subscription.updated" }

      context "when after_commit is true" do
        let(:activity_loggable_after_commit) { true }

        it "produces the activity log after commit" do
          test_service_with_activity_loggable(after_commit: true, action_match_updated: true)
        end
      end

      context "when after_commit is false" do
        let(:activity_loggable_after_commit) { false }

        it "produces the activity log before commit" do
          test_service_with_activity_loggable(after_commit: false, action_match_updated: true)
        end
      end
    end

    context "when action does not match /updated/" do
      let(:activity_loggable_action) { "subscription.created" }

      context "when after_commit is true" do
        let(:activity_loggable_after_commit) { true }

        it "produces the activity log" do
          test_service_with_activity_loggable(after_commit: true, action_match_updated: false)
        end
      end

      context "when after_commit is false" do
        let(:activity_loggable_after_commit) { false }

        it "produces the activity log" do
          test_service_with_activity_loggable(after_commit: false, action_match_updated: false)
        end
      end
    end
  end

  context "with validation error" do
    [true, false].each do |legacy_result|
      context "when extra hash is valid" do
        it "sets the extra details" do
          service_class = Class.new(described_class) do
            unless legacy_result
              const_set(:Result, BaseResult)
            end

            def call
              result.validation_failure!(
                errors: {threshold: ["value_is_not_in_range"]},
                extra: {threshold: {value_is_not_in_range: {min: 12, max: 100}}}
              )
            end
          end
          err = service_class.call
          expect(err).not_to be_success
          expect(err.error.messages).to eq(threshold: ["value_is_not_in_range"])
          expect(err.error.extra).to eq(threshold: {value_is_not_in_range: {min: 12, max: 100}})
        end
      end

      context "when extra hash doesn't match errors field code" do
        it "raises an error" do
          service_class = Class.new(described_class) do
            unless legacy_result
              const_set(:Result, BaseResult)
            end

            def call
              result.validation_failure!(
                errors: {threshold: ["value_is_not_in_range"]},
                extra: {NOT_threshold: {value_is_not_in_range: {min: 12, max: 100}}}
              )
            end
          end
          expect { service_class.call }.to raise_error(ArgumentError)
        end
      end

      context "when extra hash doesn't match errors codes for field" do
        it "raises an error" do
          service_class = Class.new(described_class) do
            unless legacy_result
              const_set(:Result, BaseResult)
            end

            def call
              result.validation_failure!(
                errors: {threshold: ["value_is_not_in_range"]},
                extra: {threshold: {error_not_in_array: {min: 12, max: 100}}}
              )
            end
          end
          expect { service_class.call }.to raise_error(ArgumentError)
        end
      end
    end
  end
end
