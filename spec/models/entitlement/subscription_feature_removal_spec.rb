# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionFeatureRemoval, type: :model do
  subject { build(:subscription_feature_removal) }

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:feature).class_name("Entitlement::Feature")
    end
  end
end
