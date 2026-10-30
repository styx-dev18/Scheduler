require "opentelemetry/sdk"

RSpec.shared_context "with in-memory tracing" do
  let(:span_exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }
  let(:tracer_provider) do
    OpenTelemetry::SDK::Trace::TracerProvider.new.tap do |provider|
      provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(span_exporter))
    end
  end
  let(:test_tracer) { tracer_provider.tracer("spec") }

  before do
    stub_const("Appointments::Placement::TRACER", test_tracer)
    stub_const("Availability::FreeBays::TRACER", test_tracer)
    stub_const("Availability::FreeTechnicians::TRACER", test_tracer)
  end

  def finished_spans(name = nil)
    spans = span_exporter.finished_spans
    name ? spans.select { |span| span.name == name } : spans
  end
end
