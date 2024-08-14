# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::UsageThresholds::CheckService, type: :service do
  subject(:service) { described_class.new(lifetime_usage: lifetime_usage) }

  let(:lifetime_usage) { create(:lifetime_usage, subscription:, recalculate_current_usage:, recalculate_invoiced_usage:) }
  let(:recalculate_current_usage) { true }
  let(:recalculate_invoiced_usage) { true }
  let(:subscription) { create(:subscription, customer_id: customer.id) }
  let(:organization) { subscription.organization }
  let(:customer) { create(:customer) }

  def create_thresholds(subscription, amounts:, recurring: nil)
    amounts.each do |amount|
      subscription.plan.usage_thresholds.create!(amount_cents: amount)
    end
    if recurring
      subscription.plan.usage_thresholds.create!(amount_cents: recurring, recurring: true)
    end
  end

  def validate_thresholds(mapping)
    mapping.each do |(invoiced, current), expected_threshold_amounts|
      lifetime_usage.invoiced_usage_amount_cents = invoiced
      lifetime_usage.current_usage_amount_cents = current
      result = service.call

      expect(result.passed_thresholds.map(&:amount_cents)).to eq(expected_threshold_amounts), "invoiced:#{invoiced} current:#{current} expected_thresholds: #{expected_threshold_amounts} got: #{result.passed_thresholds.map(&:amount_cents)}"
    end
  end

  context "without recurring thresholds" do
    context "with no fixed thresholds" do
      before do
        create_thresholds(subscription, amounts: [])
      end

      it "calculates the passed thresholds correctly" do
        validate_thresholds({
          [0, 7] => [],
          [0, 10] => [],
          [9, 2] => [],
          [11, 1] => [],
          [11, 10] => []
        })
      end
    end

    context "with 1 fixed threshold" do
      before do
        create_thresholds(subscription, amounts: [10])
      end

      it "calculates the passed thresholds correctly" do
        validate_thresholds({
          [0, 7] => [],
          [0, 10] => [10],
          [9, 2] => [10],
          [11, 1] => [],
          [11, 10] => []
        })
      end
    end

    context "with multiple fixed thresholds" do
      before do
        create_thresholds(subscription, amounts: [10, 20, 31, 40])
      end

      it "calculates the passed thresholds correctly" do
        validate_thresholds({
          [0, 7] => [],
          [0, 10] => [10],
          [0, 31] => [10, 20, 31],
          [9, 2] => [10],
          [9, 20] => [10, 20],
          [9, 31] => [10, 20, 31, 40],
          [11, 1] => [],
          [11, 10] => [20],
          [21, 20] => [31, 40],
          [40, 2] => [],
          [50, 0] => []
        })
      end
    end
  end

  context "with recurring thresholds" do
    context "with no fixed thresholds" do
      before do
        create_thresholds(subscription, amounts: [], recurring: 10)
      end

      it "calculates the passed thresholds correctly" do
        validate_thresholds({
          [0, 7] => [],
          [0, 10] => [10],
          [9, 2] => [10],
          [11, 1] => [],
          [11, 8] => [],
          [11, 9] => [10],
          [11, 10] => [10],
          [11, 20] => [10],
          [202, 7] => [],
          [202, 8] => [10]
        })
      end
    end

    context "with 1 fixed threshold" do
      before do
        create_thresholds(subscription, amounts: [10], recurring: 5)
      end

      it "calculates the passed thresholds correctly" do
        validate_thresholds({
          [0, 7] => [],
          [0, 10] => [10],
          [0, 15] => [10, 5],
          [0, 20] => [10, 5],
          [9, 2] => [10],
          [9, 6] => [10, 5],
          [9, 20] => [10, 5],
          [11, 3] => [],
          [11, 4] => [5],
          [11, 20] => [5]
        })
      end
    end

    context "with multiple fixed thresholds" do
      before do
        create_thresholds(subscription, amounts: [10, 20, 31, 40], recurring: 5)
      end

      it "calculates the passed thresholds correctly" do
        validate_thresholds({
          [0, 7] => [],
          [0, 10] => [10],
          [0, 31] => [10, 20, 31],
          [0, 44] => [10, 20, 31, 40],
          [0, 45] => [10, 20, 31, 40, 5],
          [9, 2] => [10],
          [9, 20] => [10, 20],
          [9, 31] => [10, 20, 31, 40],
          [9, 37] => [10, 20, 31, 40, 5],
          [11, 1] => [],
          [11, 10] => [20],
          [21, 20] => [31, 40],
          [21, 24] => [31, 40, 5],
          [40, 2] => [],
          [40, 5] => [5],
          [41, 4] => [5],
          [49, 1] => [5],
          [50, 0] => [],
          [50, 5] => [5]
        })
      end
    end
  end
end
