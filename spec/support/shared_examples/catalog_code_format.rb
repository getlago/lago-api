# frozen_string_literal: true

# Shared validation for the slug-safe `code` on v2 catalog objects.
# Usage: it_behaves_like "a catalog code", :product
RSpec.shared_examples "a catalog code" do |factory|
  describe "code format" do
    it "allows a slug-safe code" do
      record = build(factory, code: "valid_code-1.2")
      record.valid?
      expect(record.errors[:code]).to be_empty
    end

    it "rejects a code containing a slash" do
      record = build(factory, code: "a/b")
      record.valid?
      expect(record.errors.where(:code, :invalid)).to be_present
    end

    it "rejects a code containing a space" do
      record = build(factory, code: "a b")
      record.valid?
      expect(record.errors.where(:code, :invalid)).to be_present
    end

    it "rejects the path-segment specials . and .." do
      %w[. ..].each do |code|
        record = build(factory, code:)
        record.valid?
        expect(record.errors.where(:code, :invalid)).to be_present
      end
    end
  end
end
