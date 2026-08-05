# frozen_string_literal: true

require "rails_helper"

RSpec.describe TypedResults do
  let(:service_class) do
    Class.new(BaseService) do
      include TypedResults

      const_set(:RESULTS, {
        with_kwargs: BaseResult[:value],
        with_positional: BaseResult[:echo],
        failing: BaseResult,
        bare: BaseResult
      }.freeze)

      def with_kwargs(base:, multiplier:)
        result.value = base * multiplier
        result
      end

      def with_positional(echo)
        result.echo = echo
        result
      end

      def failing
        result.service_failure!(code: "boom", message: "nope")
      end

      def bare
        result
      end
    end
  end

  describe ".call" do
    it "routes to the target method and returns the declared typed Result" do
      result = service_class.call(:with_kwargs, base: 3, multiplier: 4)

      expect(result).to be_a(BaseResult)
      expect(result.value).to eq(12)
      expect(result.success?).to be(true)
    end

    it "forwards positional arguments to the method" do
      expect(service_class.call(:with_positional, "hello").echo).to eq("hello")
    end

    it "returns a bare BaseResult when no attributes are declared" do
      result = service_class.call(:bare)

      expect(result).to be_a(BaseResult)
      expect(result.success?).to be(true)
    end

    it "surfaces failures on the result" do
      result = service_class.call(:failing)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ServiceFailure)
    end

    it "raises when the method is not declared in RESULTS" do
      expect { service_class.call(:unknown) }
        .to raise_error(ArgumentError, /not declared in RESULTS/)
    end
  end

  describe ".call!" do
    it "returns the result on success" do
      expect(service_class.call!(:with_kwargs, base: 2, multiplier: 5).value).to eq(10)
    end

    it "raises the error on failure" do
      expect { service_class.call!(:failing) }.to raise_error(BaseService::ServiceFailure)
    end
  end
end
