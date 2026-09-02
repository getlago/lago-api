# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::ResolveUnitsService do
  subject(:result) { described_class.call(subscription_rate_card: current_version, from:, to:) }

  let(:organization) { create(:organization, timezone: "UTC") }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, proration: true) }

  let(:current_version) { versions.last }

  # August 2025 has 31 days, so the day counts below are all exact. The window is stated
  # separately from the version boundaries: a rate change narrows the window without moving
  # the moments the quantity changed.
  let(:card_start) { Time.utc(2025, 8, 1) }
  let(:from) { card_start }
  let(:to) { Time.utc(2025, 8, 31).end_of_day }

  def create_version(units:, started_at:, ended_at: nil)
    create(
      :subscription_rate_card,
      organization:,
      subscription:,
      customer:,
      rate_card:,
      units:,
      started_at:,
      ended_at:,
      billing_anchor_date: Date.new(2025, 8, 1),
      next_billing_at: Time.utc(2025, 9, 1)
    )
  end

  describe "#call" do
    context "with a single version covering the whole window" do
      let(:versions) { [create_version(units: 7, started_at: card_start)] }

      it "returns that version's units untouched" do
        expect(result.units).to eq(7)
      end
    end

    context "with a units change mid-window" do
      # 5 units for Aug 1-10 (10 days), 9 units for Aug 11-31 (21 days).
      let(:versions) do
        [
          create_version(units: 5, started_at: card_start, ended_at: Time.utc(2025, 8, 11)),
          create_version(units: 9, started_at: Time.utc(2025, 8, 11))
        ]
      end

      it "time-weights the two quantities" do
        # (5 * 10 + 9 * 21) / 31
        expect(result.units.round(6)).to eq(BigDecimal("7.709677"))
      end

      context "when the rate card does not prorate" do
        let(:rate_card) { create(:rate_card, organization:, product:, proration: false) }

        it "bills the quantity standing at the end of the window" do
          expect(result.units).to eq(9)
        end
      end
    end

    context "with a units decrease mid-window" do
      # 9 units for Aug 1-20 (20 days), 2 units for Aug 21-31 (11 days).
      let(:versions) do
        [
          create_version(units: 9, started_at: card_start, ended_at: Time.utc(2025, 8, 21)),
          create_version(units: 2, started_at: Time.utc(2025, 8, 21))
        ]
      end

      it "weights the decrease over the days it applied" do
        # (9 * 20 + 2 * 11) / 31
        expect(result.units.round(6)).to eq(BigDecimal("6.516129"))
      end
    end

    context "with several changes in the window" do
      # This is the composition scenario: 5 units from Aug 1, 9 from Aug 11, 2 from Aug 21.
      let(:versions) do
        [
          create_version(units: 5, started_at: card_start, ended_at: Time.utc(2025, 8, 11)),
          create_version(units: 9, started_at: Time.utc(2025, 8, 11), ended_at: Time.utc(2025, 8, 21)),
          create_version(units: 2, started_at: Time.utc(2025, 8, 21))
        ]
      end

      it "weights every version over the whole window" do
        # (5 * 10 + 9 * 10 + 2 * 11) / 31
        expect(result.units.round(6)).to eq(BigDecimal("5.225806"))
      end

      # A rate effective_from splits the cycle into two priced segments. Each segment resolves
      # its own quantity, and the two must tile the window exactly: no day counted twice, none
      # dropped. Segment days are 14 + 17 = 31.
      context "when a rate change splits the window" do
        context "with the first segment, Aug 1 to Aug 14" do
          let(:to) { Time.utc(2025, 8, 14).end_of_day }

          it "weights only the versions overlapping that segment" do
            # (5 * 10 + 9 * 4) / 14
            expect(result.units.round(6)).to eq(BigDecimal("6.142857"))
          end
        end

        context "with the second segment, Aug 15 to Aug 31" do
          let(:from) { Time.utc(2025, 8, 15) }

          it "weights only the versions overlapping that segment" do
            # (9 * 6 + 2 * 11) / 17
            expect(result.units.round(6)).to eq(BigDecimal("4.470588"))
          end
        end
      end

      context "when the rate card does not prorate" do
        let(:rate_card) { create(:rate_card, organization:, product:, proration: false) }

        it "bills the last quantity of the window" do
          expect(result.units).to eq(2)
        end
      end
    end

    context "with several changes on the same day" do
      # Days are counted by calendar date, so the two intra-day versions weigh nothing and the
      # day belongs to the one that closed it.
      let(:versions) do
        [
          create_version(units: 5, started_at: card_start, ended_at: Time.utc(2025, 8, 11, 9)),
          create_version(units: 9, started_at: Time.utc(2025, 8, 11, 9), ended_at: Time.utc(2025, 8, 11, 15)),
          create_version(units: 2, started_at: Time.utc(2025, 8, 11, 15))
        ]
      end

      it "gives the day to the version standing at the end of it" do
        # (5 * 10 + 9 * 0 + 2 * 21) / 31
        expect(result.units.round(6)).to eq(BigDecimal("2.967742"))
      end
    end

    context "with a version that closed before the window" do
      let(:versions) do
        [
          create_version(units: 100, started_at: Time.utc(2025, 7, 1), ended_at: card_start),
          create_version(units: 4, started_at: card_start)
        ]
      end

      it "ignores it" do
        expect(result.units).to eq(4)
      end
    end

    context "with a version starting after the window" do
      let(:versions) do
        [
          create_version(units: 4, started_at: card_start, ended_at: Time.utc(2025, 9, 10)),
          create_version(units: 100, started_at: Time.utc(2025, 9, 10))
        ]
      end

      it "ignores it" do
        expect(result.units).to eq(4)
      end
    end

    context "when units are nil" do
      let(:versions) { [create_version(units: nil, started_at: card_start)] }

      it "resolves to zero" do
        expect(result.units).to eq(0)
      end
    end
  end
end
