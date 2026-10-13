# frozen_string_literal: true

require "rails_helper"
require "lago/database/schema_rewriter"

RSpec.describe Lago::Database::SchemaRewriter do
  describe ".target_schema" do
    subject(:target_schema) { described_class.target_schema(schema_search_path) }

    context "with a custom schema" do
      let(:schema_search_path) { "lago" }

      it { is_expected.to eq("lago") }
    end

    context "with a custom schema followed by other schemas" do
      let(:schema_search_path) { " \"Lago\" , public" }

      it { is_expected.to eq("Lago") }
    end

    context "with the public schema" do
      let(:schema_search_path) { "public" }

      it { is_expected.to be_nil }
    end

    context "with the default search path" do
      let(:schema_search_path) { "\"$user\", public" }

      it { is_expected.to be_nil }
    end

    context "without a search path" do
      let(:schema_search_path) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe "#call" do
    subject(:rewritten) { described_class.new(sql, schema:).call }

    let(:schema) { "lago" }
    let(:sql) do
      <<~SQL
        DROP INDEX IF EXISTS public.index_customers_on_name;
        DROP TABLE IF EXISTS public.customers;
        DROP TYPE IF EXISTS public.customer_type;
        DROP EXTENSION IF EXISTS pg_trgm;
        DROP SCHEMA IF EXISTS partman;
        CREATE SCHEMA partman;
        CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
        CREATE TYPE public.customer_type AS ENUM ('company', 'individual');
        CREATE SEQUENCE public.customers_id_seq;
        CREATE TABLE public.customers (
            id bigint DEFAULT nextval('public.customers_id_seq'::regclass) NOT NULL,
            customer_type public.customer_type,
            name character varying
        );
        CREATE INDEX index_customers_on_name ON public.customers USING gin (name public.gin_trgm_ops);
        CREATE INDEX index_customers_on_type ON public.customers USING btree (customer_type) WHERE (customer_type = 'company'::public.customer_type);
        CREATE FUNCTION public.record_deletion() RETURNS trigger
            LANGUAGE plpgsql
            AS $$ BEGIN INSERT INTO public.deleted_records SELECT 1; RETURN OLD; END; $$;
        CREATE TABLE public.deleted_records (id bigint);
        ALTER TABLE ONLY public.customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
        SET search_path TO "$user", public;
        INSERT INTO "schema_migrations" (version) VALUES ('20250120151959');
      SQL
    end

    it "moves the objects created by the dump to the schema" do
      expect(rewritten).to eq(<<~SQL)
        DROP INDEX IF EXISTS "lago".index_customers_on_name;
        DROP TABLE IF EXISTS "lago".customers;
        DROP TYPE IF EXISTS "lago".customer_type;
        CREATE SCHEMA IF NOT EXISTS partman;
        CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
        CREATE TYPE "lago".customer_type AS ENUM ('company', 'individual');
        CREATE SEQUENCE "lago".customers_id_seq;
        CREATE TABLE "lago".customers (
            id bigint DEFAULT nextval('"lago".customers_id_seq'::regclass) NOT NULL,
            customer_type "lago".customer_type,
            name character varying
        );
        CREATE INDEX index_customers_on_name ON "lago".customers USING gin (name public.gin_trgm_ops);
        CREATE INDEX index_customers_on_type ON "lago".customers USING btree (customer_type) WHERE (customer_type = 'company'::"lago".customer_type);
        CREATE FUNCTION "lago".record_deletion() RETURNS trigger
            LANGUAGE plpgsql
            AS $$ BEGIN INSERT INTO "lago".deleted_records SELECT 1; RETURN OLD; END; $$;
        CREATE TABLE "lago".deleted_records (id bigint);
        ALTER TABLE ONLY "lago".customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
        SET search_path TO "lago", public;
        INSERT INTO "schema_migrations" (version) VALUES ('20250120151959');
      SQL
    end

    context "with a schema name that needs quoting" do
      let(:schema) { "Lago" }
      let(:sql) { "CREATE TABLE public.customers (id bigint);\nSET search_path TO \"$user\", public;\n" }

      it "quotes the schema" do
        expect(rewritten).to eq("CREATE TABLE \"Lago\".customers (id bigint);\nSET search_path TO \"Lago\", public;\n")
      end
    end

    context "with the structure file" do
      let(:sql) { Rails.root.join("db/structure.sql").read }

      it "keeps only extension objects in public" do
        remaining = rewritten.scan(/\bpublic\.(\w+)/).flatten.uniq

        expect(remaining).to eq(["gin_trgm_ops"])
      end
    end

    context "with the initial migration" do
      let(:sql) { Rails.root.join("db/migrate/20250122112050_initial_migration.rb").read }

      it "moves every object to the schema" do
        remaining = rewritten.scan(/\bpublic\.(\w+)/).flatten.uniq

        expect(remaining).to be_empty
      end
    end
  end
end
