RSpec.describe "app/domain architecture" do
  root = File.expand_path("../..", __dir__)
  files = Dir.glob(File.expand_path("../../app/domain/**/*.rb", __dir__))
  forbidden = /\b(?:ActiveRecord|ApplicationRecord)\b|\bRails\./

  it "has domain files to check" do
    expect(files).not_to be_empty
  end

  it "references neither ActiveRecord, ApplicationRecord nor Rails" do
    offenders = files.flat_map do |file|
      File.foreach(file).each_with_index.filter_map do |line, index|
        "#{file.delete_prefix("#{root}/")}:#{index + 1}" if line.match?(forbidden)
      end
    end

    expect(offenders).to eq([])
  end
end
