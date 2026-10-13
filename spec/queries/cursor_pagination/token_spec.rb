# frozen_string_literal: true

require "rails_helper"

RSpec.describe CursorPagination::Token do
  let(:record) { build_stubbed(:product, created_at: Time.zone.parse("2026-09-28T10:11:12.123456Z")) }

  def encode_payload(payload)
    Base64.urlsafe_encode64(payload.to_json, padding: false)
  end

  describe ".encode" do
    subject(:token) { described_class.encode(table: "products", record:) }

    it "encodes the version, the table, the sort and the key of the record" do
      expect(JSON.parse(Base64.urlsafe_decode64(token))).to eq(
        "v" => 1,
        "o" => {"t" => "products", "s" => "created_at:desc,id:desc"},
        "k" => ["2026-09-28T10:11:12.123456Z", record.id]
      )
    end

    it "is URL safe and unpadded" do
      expect(token).to match(/\A[A-Za-z0-9_-]+\z/)
    end

    context "with a sort on other columns than the key" do
      subject(:token) { described_class.encode(table: "products", record:, sort: {name: :asc, id: :asc}) }

      it "raises an argument error, since the cursor could not be resumed" do
        expect { token }.to raise_error(ArgumentError, /created_at then id/)
      end
    end

    context "with a sort mixing directions" do
      subject(:token) { described_class.encode(table: "products", record:, sort: {created_at: :desc, id: :asc}) }

      it "raises an argument error" do
        expect { token }.to raise_error(ArgumentError, /single direction/)
      end
    end
  end

  describe ".decode" do
    subject(:decode) { described_class.decode(value, table: "products", param: :after) }

    let(:value) { encode_payload(payload) }
    let(:payload) { {v: 1, o: {t: "products", s: "created_at:desc,id:desc"}, k: ["2026-09-28T10:11:12.123456Z", record.id]} }

    it "returns the key of the anchor row, keeping the microseconds" do
      created_at, id = decode

      expect(created_at).to eq(Time.utc(2026, 9, 28, 10, 11, Rational(12_123_456, 1_000_000)))
      expect(created_at.usec).to eq(123_456)
      expect(id).to eq(record.id)
    end

    it "round-trips an encoded token" do
      expect(described_class.decode(described_class.encode(table: "products", record:), table: "products", param: :after))
        .to eq([record.created_at.utc, record.id])
    end

    shared_examples "an invalid cursor" do |reason|
      it "raises an invalid cursor error keyed by the parameter" do
        expect { decode }.to raise_error(CursorPagination::Error) { |error|
          expect(error.code).to eq("invalid_pagination_cursor")
          expect(error.details).to eq(after: {reason:})
        }
      end
    end

    context "when the value is an array" do
      let(:value) { [encode_payload(payload)] }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the value is a hash" do
      let(:value) { {"k" => encode_payload(payload)} }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the value is not a string" do
      let(:value) { 1 }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the value is longer than 512 bytes" do
      let(:value) { "a" * 513 }

      it_behaves_like "an invalid cursor", "too_long"
    end

    context "with characters outside of the URL safe alphabet" do
      let(:value) { Base64.strict_encode64(payload.to_json) }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the value is not Base64" do
      let(:value) { "a" }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the value is not JSON" do
      let(:value) { Base64.urlsafe_encode64("not json", padding: false) }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the value is not valid UTF-8" do
      let(:value) { Base64.urlsafe_encode64("\xFF\xFE".b, padding: false) }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the JSON is not an object" do
      let(:payload) { [1, 2] }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "with an extra key" do
      let(:payload) { super().merge(x: 1) }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "with a missing key" do
      let(:payload) { super().except(:k) }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "with an unknown version" do
      let(:payload) { super().merge(v: 2) }

      it_behaves_like "an invalid cursor", "unsupported_version"
    end

    context "with a version that is not an integer" do
      let(:payload) { super().merge(v: 1.0) }

      it_behaves_like "an invalid cursor", "unsupported_version"
    end

    context "with a malformed ordering" do
      let(:payload) { super().merge(o: "products") }

      it_behaves_like "an invalid cursor", "malformed"
    end

    context "when the cursor was minted for another table" do
      let(:payload) { super().merge(o: {t: "product_categories", s: "created_at:desc,id:desc"}) }

      it_behaves_like "an invalid cursor", "wrong_resource"
    end

    context "when the cursor was minted under another sort" do
      let(:payload) { super().merge(o: {t: "products", s: "created_at:desc,id:asc"}) }

      it "raises an expired cursor error" do
        expect { decode }.to raise_error(CursorPagination::Error) { |error|
          expect(error.code).to eq("pagination_cursor_expired")
          expect(error.details).to eq(after: {reason: "sort_changed"})
        }
      end
    end

    context "when decoded under a sort on other columns than the key" do
      subject(:decode) { described_class.decode(value, table: "products", param: :after, sort: {name: :asc, id: :asc}) }

      it "raises an argument error" do
        expect { decode }.to raise_error(ArgumentError, /created_at then id/)
      end
    end

    context "when decoded for an endpoint declaring another sort" do
      subject(:decode) { described_class.decode(value, table: "products", param: :after, sort: {created_at: :asc, id: :asc}) }

      it "raises an expired cursor error" do
        expect { decode }.to raise_error(CursorPagination::Error) { |error|
          expect(error.code).to eq("pagination_cursor_expired")
        }
      end
    end

    context "when encoded under another sort" do
      let(:value) { described_class.encode(table: "products", record:, sort: {created_at: :asc, id: :asc}) }

      it "writes that sort in the cursor" do
        expect(JSON.parse(Base64.urlsafe_decode64(value)).dig("o", "s")).to eq("created_at:asc,id:asc")
      end
    end

    context "with a key of the wrong size" do
      let(:payload) { super().merge(k: [record.id]) }

      it_behaves_like "an invalid cursor", "malformed_key"
    end

    context "with a timestamp without microseconds" do
      let(:payload) { super().merge(k: ["2026-09-28T10:11:12Z", record.id]) }

      it_behaves_like "an invalid cursor", "malformed_key"
    end

    context "with an impossible timestamp" do
      let(:payload) { super().merge(k: ["2026-13-28T10:11:12.123456Z", record.id]) }

      it_behaves_like "an invalid cursor", "malformed_key"
    end

    context "with a malformed UUID" do
      let(:payload) { super().merge(k: ["2026-09-28T10:11:12.123456Z", "not-a-uuid"]) }

      it_behaves_like "an invalid cursor", "malformed_key"
    end

    context "with a non-string key" do
      let(:payload) { super().merge(k: [1_790_000_000, record.id]) }

      it_behaves_like "an invalid cursor", "malformed_key"
    end
  end
end
