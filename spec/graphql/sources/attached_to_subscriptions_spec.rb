# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::AttachedToSubscriptions do
  subject(:source) { described_class.new }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  describe "#fetch" do
    it "flags cards billed directly or through a subscribed plan" do
      direct = create(:rate_card, organization:, product:)
      create(:subscription_rate_card, organization:, rate_card: direct)

      through_plan = create(:rate_card, organization:, product:)
      plan = create(:plan, organization:)
      create(:plan_rate_card, organization:, plan:, rate_card: through_plan)
      create(:subscription, organization:, plan:)

      plan_without_subscription = create(:rate_card, organization:, product:)
      create(:plan_rate_card, organization:, rate_card: plan_without_subscription)

      result = source.fetch([direct.id, through_plan.id, plan_without_subscription.id])

      expect(result).to eq([true, true, false])
    end
  end
end
