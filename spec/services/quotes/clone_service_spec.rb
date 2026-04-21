# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::CloneService do
  subject(:result) { described_class.call(quote:) }

  let(:organization) { create(:organization, feature_flags: ["quote"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, status: :draft) }

  context "when license is premium", :premium do
    it "clones a draft quote into a new draft version" do
      quote # ensure the source exists before the change block
      freeze_time do
        expect { result }.to change(Quote, :count).by(1)

        expect(result).to be_success
        cloned = result.quote
        expect(cloned.id).not_to eq(quote.id)
        expect(cloned.status).to eq("draft")
        expect(cloned.version).to eq(2)
        expect(cloned.sequential_id).to eq(quote.sequential_id)
        expect(cloned.number).to eq(quote.number)
        expect(cloned.customer_id).to eq(customer.id)
        expect(cloned.subscription_id).to eq(quote.subscription_id)
        expect(cloned.order_type).to eq(quote.order_type)
        expect(cloned.voided_at).to be_nil
        expect(cloned.void_reason).to be_nil

        quote.reload
        expect(quote.status).to eq("voided")
        expect(quote.void_reason).to eq("superseded")
        expect(quote.voided_at).to eq(Time.current)
      end
    end

    context "when the source quote is approved" do
      let(:quote) { create(:quote, organization:, customer:, status: :approved) }

      it "supersedes the source and returns a fresh draft" do
        expect(result).to be_success
        expect(result.quote.status).to eq("draft")
        expect(result.quote.version).to eq(2)

        quote.reload
        expect(quote.status).to eq("voided")
        expect(quote.void_reason).to eq("superseded")
      end
    end

    context "when the source quote is voided" do
      let(:quote) do
        create(
          :quote,
          organization:,
          customer:,
          status: :voided,
          void_reason: "manual",
          voided_at: 1.day.ago
        )
      end

      it "resets voided_at and void_reason on the clone" do
        expect(result).to be_success
        cloned = result.quote
        expect(cloned.status).to eq("draft")
        expect(cloned.voided_at).to be_nil
        expect(cloned.void_reason).to be_nil
      end

      it "does not re-void the source" do
        original_voided_at = quote.voided_at
        original_void_reason = quote.void_reason

        expect(result).to be_success

        quote.reload
        expect(quote.status).to eq("voided")
        expect(quote.void_reason).to eq(original_void_reason)
        expect(quote.voided_at.to_i).to eq(original_voided_at.to_i)
      end

      context "when another active version exists at a higher version" do
        let!(:active_sibling) do
          create(
            :quote,
            organization:,
            customer:,
            sequential_id: quote.sequential_id,
            version: quote.version + 1,
            status: :approved
          )
        end

        it "voids the active sibling with superseded" do
          expect(result).to be_success
          expect(result.quote.version).to eq(active_sibling.version + 1)

          active_sibling.reload
          expect(active_sibling.status).to eq("voided")
          expect(active_sibling.void_reason).to eq("superseded")
        end
      end
    end

    context "when cloning from an older version while a newer active version exists" do
      let(:quote) { create(:quote, organization:, customer:, status: :draft, version: 1) }
      let!(:v2) { create(:quote, organization:, customer:, sequential_id: quote.sequential_id, version: 2, status: :draft) }
      let!(:v3) do
        create(
          :quote,
          organization:,
          customer:,
          sequential_id: quote.sequential_id,
          version: 3,
          status: :voided,
          void_reason: "manual",
          voided_at: 1.day.ago
        )
      end

      it "creates v4 and supersedes all active prior versions" do
        expect(result).to be_success
        cloned = result.quote
        expect(cloned.version).to eq(4)
        expect(cloned.sequential_id).to eq(quote.sequential_id)
        expect(cloned.status).to eq("draft")

        quote.reload
        expect(quote.status).to eq("voided")
        expect(quote.void_reason).to eq("superseded")

        v2.reload
        expect(v2.status).to eq("voided")
        expect(v2.void_reason).to eq("superseded")
      end

      it "does not re-void the already voided v3" do
        original_voided_at = v3.voided_at
        original_void_reason = v3.void_reason

        expect(result).to be_success

        v3.reload
        expect(v3.status).to eq("voided")
        expect(v3.void_reason).to eq(original_void_reason)
        expect(v3.voided_at.to_i).to eq(original_voided_at.to_i)
      end
    end

    context "when the MAX version is not the source's version" do
      let(:quote) do
        create(
          :quote,
          organization:,
          customer:,
          status: :voided,
          void_reason: "manual",
          voided_at: 1.day.ago,
          version: 1
        )
      end

      before do
        create(
          :quote,
          organization:,
          customer:,
          sequential_id: quote.sequential_id,
          version: 3,
          status: :approved
        )
      end

      it "uses MAX(version) + 1 rather than source.version + 1" do
        expect(result).to be_success
        expect(result.quote.version).to eq(4)
      end
    end

    context "when the source has owners" do
      let(:owner_a) { create(:membership, organization:).user }
      let(:owner_b) { create(:membership, organization:).user }

      before do
        create(:quote_owner, quote:, organization:, user: owner_a)
        create(:quote_owner, quote:, organization:, user: owner_b)
      end

      it "copies all owners onto the clone" do
        expect { result }.to change(QuoteOwner, :count).by(2)

        expect(result).to be_success
        expect(result.quote.owners).to match_array([owner_a, owner_b])
      end

      it "does not strip owners from the source" do
        expect(result).to be_success
        expect(quote.reload.owners).to match_array([owner_a, owner_b])
      end
    end

    context "when a quote in another organization shares the same sequential_id" do
      let(:other_organization) { create(:organization, feature_flags: ["quote"]) }
      let(:other_customer) { create(:customer, organization: other_organization) }

      before do
        create(
          :quote,
          organization: other_organization,
          customer: other_customer,
          sequential_id: quote.sequential_id,
          version: 99,
          status: :draft
        )
      end

      it "does not factor the foreign quote into the MAX(version) computation" do
        expect(result).to be_success
        expect(result.quote.version).to eq(2)
      end
    end

    context "when quote is nil" do
      let(:quote) { nil }

      it "returns a not_found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when the quote feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns a forbidden failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end
  end

  context "when license is not premium" do
    it "returns a forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end
end
