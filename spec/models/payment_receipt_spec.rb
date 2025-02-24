# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipt, type: :model do
  subject(:payment_receipt) { build(:payment_receipt) }

  it { is_expected.to belong_to(:payment) }
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to have_one_attached(:file) }

  describe "#file_url" do
    before do
      payment_receipt.save!
      payment_receipt.file.attach(
        io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
        filename: "payment_receipt.pdf",
        content_type: "application/pdf"
      )
    end

    it "returns the file url" do
      file_url = payment_receipt.file_url

      expect(file_url).to be_present
      expect(file_url).to include(ENV["LAGO_API_URL"])
    end
  end
end
