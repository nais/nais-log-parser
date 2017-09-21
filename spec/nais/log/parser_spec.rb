require "spec_helper"

RSpec.describe Nais::Log::Parser do
  it "has a version number" do
    expect(Nais::Log::Parser::VERSION).not_to be nil
  end

  it "does flatten hash" do
    expect(Nais::Log::Parser.flatten_hash({"a"=>"b", "c.c"=>"d", "e"=>{"f"=>"g"}, "h"=>{"i"=>"j", "k"=>{"l.l"=>"m"}}})).
      to eql({"a"=>"b", "c_c"=>"d", "e_f"=>"g", "h_i"=>"j", "h_k_l_l"=>"m"})
  end

  it "does not find exception" do
    expect(Nais::Log::Parser.get_exceptions('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does find single exception" do
    expect(Nais::Log::Parser.get_exceptions('Exception in thread "main" java.util.NoSuchElementException: foo bar')).
      to eql('NoSuchElementException')
  end
  it "does remove duplicate exception" do
    expect(Nais::Log::Parser.get_exceptions('Exception in thread "main" java.util.NoSuchElementException: NoSuchElementException')).
      to eql('NoSuchElementException')
  end

  it "does find multiple exceptions" do
    expect(Nais::Log::Parser.get_exceptions("org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'requestMappingHandlerMapping' defined in class org.springframework.web.servlet.config.annotation.DelegatingWebMvcConfiguration: Invocation of init method failed; nested exception is java.lang.IllegalStateException: Ambiguous mapping found. Cannot map 'appController' bean method")).
      to eql(['BeanCreationException', 'IllegalStateException'])
  end

  it "does prefix non standard fields" do
    expect(Nais::Log::Parser.prefix_nonstandard_fields({'type'=>'standard', 'foo'=>'nonstandard'})).
      to eql({'type'=>'standard', 'x_foo'=>'nonstandard'})
  end

  it "does remap java fields" do
    r = {'thread_name'=>'thread_name','logger_name'=>'logger_name','level'=>'LEVEL','level_value'=>10000}
    Nais::Log::Parser.remap_java_fields!(r)
    expect(r).
      to eql({'thread'=>'thread_name', 'component'=>'logger_name', 'level'=>'Level'})
  end

  it "does remap kubernetes fields" do
    r = {'stream'=>'stdout',
         'docker'=>{'container_id'=>'container_id','foo'=>'bar'},
         'kubernetes'=>{'host'=>'host',
                        'namespace_name'=>'namespace_name',
                        'container_name'=>'container_name',
                        'pod_name'=>'pod_name',
                        'foo'=>'bar'}}
    Nais::Log::Parser.remap_kubernetes_fields!(r)
    expect(r).
      to eql({'application'=>'container_name',
              'category'=>'stdout',
              'container'=>'container_id',
              'host'=>'host',
              'namespace'=>'namespace_name',
              'pod'=>'pod_name'})
  end

end
