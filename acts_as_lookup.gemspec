require 'rake'

Gem::Specification.new do |spec|
  spec.version = '0.1.0'
  spec.name = 'hopsoft-acts-as-lookup'
  spec.summary = 'Lookup tables made easy for ActiveRecord'
  spec.description = <<-DESC
    Powerful lookup table behavior added to ActiveRecord.
  DESC
  spec.authors = ['Nathan Hopkins']
  spec.email = ['natehop@gmail.com']
  spec.bindir = 'bin'
  spec.files = FileList['lib/*.rb', 'lib/**/*.rb', 'bin/*'].to_a
end

