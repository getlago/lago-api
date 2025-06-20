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
end
