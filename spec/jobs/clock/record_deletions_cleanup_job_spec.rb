# frozen_string_literal: true

require "rails_helper"

describe Clock::RecordDeletionsCleanupJob do
  subject(:cleanup_job) { described_class }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  def with_batch_size(size)
    previous = described_class.batch_size
    described_class.batch_size = size
    yield
  ensure
    described_class.batch_size = previous
  end

  describe ".perform" do
    context "when tombstones are older than the retention period" do
      it "removes them" do
        create(:record_deletion, deleted_at: 7.months.ago)

        expect { cleanup_job.perform_now }.to change(RecordDeletion, :count).to(0)
      end
    end

    context "when tombstones are newer than the retention period" do
      it "keeps them" do
        create(:record_deletion, deleted_at: 5.months.ago)

        expect { cleanup_job.perform_now }.not_to change(RecordDeletion, :count)
      end
    end

    context "when there are more expired tombstones than one batch" do
      it "removes them all" do
        create_list(:record_deletion, 3, deleted_at: 7.months.ago)

        with_batch_size(2) do
          expect { cleanup_job.perform_now }.to change(RecordDeletion, :count).to(0)
        end
      end
    end
  end
end
