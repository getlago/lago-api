# frozen_string_literal: true

# A Copy to production item type found by id in the sandbox and by code among the kept records of production. Needs `item`,
# `sandbox` and `production`.
RSpec.shared_examples "a copy to production item matched by code" do |factory, **attributes|
  let(:matched_source) { create(factory, organization: sandbox, code: "matched", **attributes) }
  let(:production_twin) { create(factory, organization: production, code: "matched", **attributes) }

  before { production_twin }

  it "finds its source in the sandbox only" do
    expect(item.find_source(matched_source.id)).to eq(matched_source)
    expect(item.find_source(production_twin.id)).to be_nil
  end

  it "finds the kept production record with the source's code" do
    expect(item.find_existing(matched_source)).to eq(production_twin)
  end

  context "when the production record is deleted" do
    before { production_twin.discard! }

    it "finds nothing" do
      expect(item.find_existing(matched_source)).to be_nil
    end
  end
end

# Every column of a copied model is copied through an attribute list (`ATTRIBUTES` by default) or left out on purpose,
# so that a new column needs a decision. `left_out` lists the columns copied otherwise or not at all, besides the ids
# and timestamps.
RSpec.shared_examples "a copy to production item copying every column" do |model, attributes: nil, left_out: []|
  it "copies every column of #{model} it does not leave out" do
    copied = (attributes || described_class::ATTRIBUTES).map(&:to_s)
    ignored = %w[id organization_id created_at updated_at deleted_at] + left_out

    expect(model.column_names - copied - ignored).to eq([])
  end
end
