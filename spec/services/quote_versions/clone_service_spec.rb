# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::CloneService do
  subject(:clone_service) { described_class.new(quote_version:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let!(:quote) { create(:quote, organization:) }
  let!(:versions) do
    QuoteVersion.transaction do
      v1 = create(:quote_version, :voided, quote:, organization:)
      v2 = create(:quote_version, :voided, quote:, organization:)
      [v1, v2]
    end
  end
  let(:quote_version) { versions.last }

  describe ".call" do
    let(:result) { clone_service.call }

    context "when the quote version is clonable", :premium do
      context "when the quote version is already voided" do
        it "creates a clone and doesn't override the original quote version" do
          expect(result).to be_success
          cloned = result.quote_version
          expect(cloned.id).not_to eq(quote_version.id)
          expect(cloned.organization_id).to eq(quote_version.organization_id)
          expect(cloned.quote_id).to eq(quote_version.quote_id)
          expect(cloned.version).to eq(quote_version.version + 1)
          expect(cloned.draft?).to eq(true)
          expect(cloned.void_reason).to eq(nil)
          expect(cloned.voided_at).to eq(nil)
          expect(cloned.approved_at).to eq(nil)

          expect(quote.reload.current_version).to eq(cloned)

          quote_version.reload
          expect(quote_version.voided?).to eq(true)
          expect(quote_version.void_reason).to eq("manual")
          expect(quote_version.voided_at).not_to eq(nil)
        end
      end

      context "when the quote version is draft" do
        let!(:versions) do
          QuoteVersion.transaction do
            v1 = create(:quote_version, :voided, quote:, organization:)
            v2 = create(:quote_version, :draft, quote:, organization:)
            [v1, v2]
          end
        end
        let(:quote_version) { versions.last }

        it "creates an clone and voids the original quote version" do
          expect(result).to be_success
          cloned = result.quote_version
          expect(cloned.id).not_to eq(quote_version.id)
          expect(cloned.organization_id).to eq(quote_version.organization_id)
          expect(cloned.quote_id).to eq(quote_version.quote_id)
          expect(cloned.version).to eq(quote_version.version + 1)
          expect(cloned.draft?).to eq(true)
          expect(cloned.void_reason).to eq(nil)
          expect(cloned.voided_at).to eq(nil)
          expect(cloned.approved_at).to eq(nil)

          expect(quote.reload.current_version).to eq(cloned)

          quote_version.reload
          expect(quote_version.voided?).to eq(true)
          expect(quote_version.void_reason).to eq("superseded")
          expect(quote_version.voided_at).not_to eq(nil)
        end
      end
    end

    context "when the quote version is not clonable", :premium do
      let(:quote_version) { create(:quote_version, :approved, quote:, organization:) }

      it "does not create a clone" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")

        quote_version.reload
        expect(quote_version.approved?).to eq(true)
        expect(quote_version.void_reason).to eq(nil)
        expect(quote_version.voided_at).to eq(nil)
      end
    end

    context "when quote does not exist", :premium do
      let(:quote_version) { nil }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("quote_version_not_found")
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end
  end
end
