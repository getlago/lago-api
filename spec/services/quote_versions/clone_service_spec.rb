# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::CloneService do
  subject(:clone_service) { described_class.new(quote_version:) }

  let_it_be(:organization) { create_default(:organization, feature_flags: ["order_forms"]) }

  before_all do
    create_default(:customer)
  end

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
      context "when the source version is voided" do
        it "creates a clone and leaves the source untouched" do
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

        it "produces a quote.version_created activity log for the clone" do
          expect(Utils::ActivityLog)
            .to have_produced("quote.version_created").after_commit.with(result.quote_version)
        end

        # The snapshot belongs to the approval the source went through, not to the clone. Carrying it
        # over would leave the new draft rendering the source's values whatever it is edited to.
        context "when the source carries an approval snapshot" do
          before do
            quote_version.update!(mention_variables: {"billing_entity_name" => "Globex SARL"})
          end

          it "leaves the clone without one, so its variables are computed live" do
            expect(result).to be_success
            expect(result.quote_version.mention_variables).to eq(nil)
          end
        end
      end

      context "when the source version is draft" do
        let!(:versions) do
          QuoteVersion.transaction do
            v1 = create(:quote_version, :voided, quote:, organization:)
            v2 = create(:quote_version, quote:, organization:)
            [v1, v2]
          end
        end

        it "creates a clone and voids the source" do
          expect(result).to be_success
          cloned = result.quote_version
          expect(cloned.id).not_to eq(quote_version.id)
          expect(cloned.version).to eq(quote_version.version + 1)
          expect(cloned.draft?).to eq(true)

          expect(quote.reload.current_version).to eq(cloned)

          quote_version.reload
          expect(quote_version.voided?).to eq(true)
          expect(quote_version.void_reason).to eq("superseded")
          expect(quote_version.voided_at).not_to eq(nil)
        end

        it "enqueues a quote.voided webhook for the superseded source" do
          expect { clone_service.call }
            .to have_enqueued_job_after_commit(SendWebhookJob)
            .with("quote.voided", quote_version)
        end

        it "produces a quote.voided activity log for the superseded source" do
          clone_service.call

          expect(Utils::ActivityLog).to have_produced("quote.voided").after_commit.with(quote_version)
        end
      end
    end

    context "with concurrent mutations", :premium do
      it "wraps the work in a per-quote lock" do
        allow(Quotes::LockService).to receive(:call).and_call_original

        result

        expect(Quotes::LockService).to have_received(:call).with(quote: quote_version.quote).at_least(:once)
      end
    end

    context "when any quote version is already approved", :premium do
      let!(:versions) do
        [create(:quote_version, :approved, quote:, organization:)]
      end
      let(:quote_version) { versions.first }

      it "rejects the clone" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["not_clonable"]})
      end
    end

    context "when an older voided version is cloned but the latest is approved", :premium do
      let!(:versions) do
        QuoteVersion.transaction do
          v1 = create(:quote_version, :voided, quote:, organization:)
          v2 = create(:quote_version, :approved, quote:, organization:)
          [v1, v2]
        end
      end
      let(:quote_version) { versions.first }

      it "rejects the clone because the quote is locked by an approved version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["not_clonable"]})
      end
    end

    context "when an unrelated draft is the active version on the quote", :premium do
      let!(:versions) do
        QuoteVersion.transaction do
          v_voided = create(:quote_version, :voided, quote:, organization:)
          v_active = create(:quote_version, quote:, organization:)
          [v_voided, v_active]
        end
      end
      let(:quote_version) { versions.first } # cloning the older voided one

      it "clones the source and voids the active draft" do
        expect(result).to be_success
        cloned = result.quote_version
        expect(cloned.draft?).to eq(true)
        expect(quote.reload.current_version).to eq(cloned)

        active_draft = versions.last.reload
        expect(active_draft.voided?).to eq(true)
        expect(active_draft.void_reason).to eq("superseded")
        expect(active_draft.voided_at).not_to eq(nil)

        quote_version.reload
        expect(quote_version.voided?).to eq(true)
        expect(quote_version.void_reason).to eq("manual")
      end
    end

    context "when cloning a middle version while a newer draft is active", :premium do
      let!(:versions) do
        QuoteVersion.transaction do
          v1 = create(:quote_version, :voided, quote:, organization:, sequential_id: 1)
          v2 = create(:quote_version, :voided, quote:, organization:, sequential_id: 2)
          v3 = create(:quote_version, quote:, organization:, sequential_id: 3)
          [v1, v2, v3]
        end
      end
      let(:quote_version) { versions[1] } # cloning V2

      # Documents that the clone takes the next sequential version (max + 1),
      # not source + 1: voided versions keep their slots, so cloning V2 yields V4.
      it "assigns the next sequential version (V4)" do
        expect(result).to be_success
        expect(result.quote_version.version).to eq(4)
        expect(versions.last.reload.voided?).to eq(true)
      end
    end

    context "when a concurrent write recreates an active version", :premium do
      let(:quote_version_dup) { quote_version.dup }

      before do
        allow(quote_version_dup).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

        allow(quote_version).to receive(:dup)
          .and_return(quote_version_dup)
      end

      it "rejects the clone with a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({status: ["active_version_exists"]})
      end
    end

    context "when quote_version does not exist", :premium do
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

    context "when the quote lock cannot be acquired", :premium do
      before do
        allow(Quotes::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
      end

      it "returns a concurrency conflict instead of raising" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(base: ["concurrency_conflict"])
      end
    end
  end
end
