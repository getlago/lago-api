# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "meilisearch rake tasks" do # rubocop:disable RSpec/DescribeClass
  before do
    Rake.application.rake_require("tasks/meilisearch")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  describe "meilisearch:reindex_invoices" do
    let(:task) { Rake::Task["meilisearch:reindex_invoices"] }

    before do
      allow(Invoice).to receive_messages(reindex!: true, index_uid: "invoices_test")
    end

    it "reindexes all invoices" do
      expect { task.invoke }.to output(/Reindexed invoices into invoices_test/).to_stdout

      expect(Invoice).to have_received(:reindex!)
    end
  end

  describe "meilisearch:clear_invoices" do
    let(:task) { Rake::Task["meilisearch:clear_invoices"] }

    before do
      allow(Invoice).to receive_messages(clear_index!: true, index_uid: "invoices_test")
    end

    it "clears the invoices index" do
      expect { task.invoke }.to output(/Cleared invoices_test/).to_stdout

      expect(Invoice).to have_received(:clear_index!)
    end
  end
end
