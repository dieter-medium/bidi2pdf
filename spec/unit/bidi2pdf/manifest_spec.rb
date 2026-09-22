# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bidi2pdf::Manifest do
  let(:result) do
    Bidi2pdf::Result.success(
      command: "render",
      output: "example.pdf",
      bytes: 182_734,
      sha256: "abcd",
      pages: 2,
      duration_ms: 842,
      navigation: { requested_url: "https://example.com", final_url: "https://example.com/", status: 200 },
      console: [],
      network_failures: [],
      warnings: []
    )
  end

  def manifest(**)
    described_class.new(result: result, input: { type: "url", url: "https://example.com" }, **)
  end

  it "carries a schema_version and the gem version" do
    hash = manifest.to_h

    expect([hash[:schema_version], hash[:bidi2pdf_version]]).to eq([1, Bidi2pdf::VERSION])
  end

  it "carries the input, output, navigation and render sections from the Result" do
    hash = manifest(navigation_duration_ms: 531).to_h

    expect(hash).to include(
      input: { type: "url", url: "https://example.com" },
      output: { path: "example.pdf", pages: 2, bytes: 182_734, sha256: "abcd" },
      navigation: { requested_url: "https://example.com", final_url: "https://example.com/", status: 200, duration_ms: 531 },
      render: { duration_ms: 842 }
    )
  end

  it "omits headers entirely when none were given" do
    expect(manifest.to_h).not_to have_key(:headers)
  end

  it "redacts a known sensitive header name" do
    hash = manifest(headers: { "Authorization" => "Bearer secret", "X-API-KEY" => "topsecret" }).to_h

    expect(hash[:headers]).to eq("Authorization" => "[REDACTED]", "X-API-KEY" => "[REDACTED]")
  end

  it "redacts a header whose name merely contains a sensitive substring" do
    hash = manifest(headers: { "X-My-Token" => "abc" }).to_h

    expect(hash[:headers]).to eq("X-My-Token" => "[REDACTED]")
  end

  it "keeps a non-sensitive header as-is" do
    hash = manifest(headers: { "X-Request-Id" => "abc-123" }).to_h

    expect(hash[:headers]).to eq("X-Request-Id" => "abc-123")
  end

  it "serializes to the same shape via #to_json" do
    expect(JSON.parse(manifest.to_json, symbolize_names: true)[:input]).to eq(type: "url", url: "https://example.com")
  end
end
