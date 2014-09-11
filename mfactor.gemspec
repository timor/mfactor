Gem::Specification.new do |s|
  s.name = 'mfactor'
  s.version = '0.0.1'
  s.date = '2014-09-09'
  s.summary = "Factor for embedded systems"
  s.description = "Ruby parser and code generator for using factor code on embedded systems, or other simplified execution environments"
  s.authors = ["timor"]
  s.email = "timor.dd@googlemail.com"
  s.files= Dir["lib/**/*.rb","tasks/**.rake","instructionset.yml","Readme.md"].to_a
  s.license = 'CC BY-NC-ND'
end
