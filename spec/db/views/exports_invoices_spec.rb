# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_invoices view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  def rows_for(id)
    ActiveRecord::Base.connection.select_all(
      "SELECT * FROM exports_invoices WHERE lago_id = #{ActiveRecord::Base.connection.quote(id)}"
    ).to_a
  end

  describe "deleted invoices" do
    # The Data Pipeline is upsert-only and cannot propagate a deletion. Filtering
    # deleted invoices out of the view dropped them from the feed entirely, so the
    # destination never learned they had changed and kept the last copy it received
    # as a draft forever. The row has to stay, carrying its deleted status, so the
    # tombstone arrives as an ordinary upsert.
    let!(:invoice) { create(:invoice, status: :draft, organization:, customer:) }

    it "keeps the invoice in the feed once deleted, carrying status 'deleted'" do
      expect(rows_for(invoice.id).first["status"]).to eq("draft")

      invoice.mark_as_deleted!

      rows = rows_for(invoice.id)
      expect(rows.size).to eq(1)
      expect(rows.first["status"]).to eq("deleted")
    end
  end

  describe "statuses that stay out of the feed" do
    # generating is transient, open and closed are deliberate product states that
    # were never part of the export contract. Only deleted (8) was added.
    %i[generating open closed].each do |status|
      context "when the invoice is #{status}" do
        let!(:invoice) { create(:invoice, status:, organization:, customer:) }

        it "is not exported" do
          expect(rows_for(invoice.id)).to be_empty
        end
      end
    end
  end

  describe "exported statuses" do
    %i[draft finalized voided failed pending].each do |status|
      context "when the invoice is #{status}" do
        let!(:invoice) { create(:invoice, status:, organization:, customer:) }

        it "is exported with status '#{status}'" do
          rows = rows_for(invoice.id)

          expect(rows.size).to eq(1)
          expect(rows.first["status"]).to eq(status.to_s)
        end
      end
    end
  end
end
