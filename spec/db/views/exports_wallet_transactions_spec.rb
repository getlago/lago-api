# frozen_string_literal: true

require "rails_helper"

describe "exports_wallet_transactions view" do # rubocop:disable RSpec/DescribeClass
  def rows_for(id)
    ActiveRecord::Base.connection.select_all(
      "SELECT * FROM exports_wallet_transactions WHERE lago_id = #{ActiveRecord::Base.connection.quote(id)}"
    ).to_a
  end

  WalletTransaction.sources.each_key do |source|
    context "with a #{source} wallet transaction" do
      let(:wallet_transaction) { create(:wallet_transaction, source:) }

      before { wallet_transaction }

      it "exports its source" do
        expect(rows_for(wallet_transaction.id).sole["source"]).to eq(source)
      end
    end
  end
end
