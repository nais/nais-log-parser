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
    expect(Nais::Log::Parser.remap_java_fields({'thread_name'=>'thread_name','logger_name'=>'logger_name','level'=>'LEVEL','level_value'=>10000})).
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
    expect(Nais::Log::Parser.remap_kubernetes_fields(r)).
      to eql({'application'=>'container_name',
              'category'=>'stdout',
              'container'=>'container_id',
              'host'=>'host',
              'namespace'=>'namespace_name',
              'pod'=>'pod_name'})
  end

  it "does return nil on non-accesslog" do
    expect(Nais::Log::Parser.parse_accesslog('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse ncsa accesslog" do
    expect(Nais::Log::Parser.parse_accesslog('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326')).
      to eql([{"remote_ip"=>"127.0.0.1",
               "user"=>"frank",
               "timestamp"=>"2000-10-10T13:55:36-07:00",
               "request"=>"GET /apache_pb.gif HTTP/1.0",
               "response_code"=>"200",
               "content_length"=>"2326"},
              nil])
  end

  it "does parse accesslog without ident" do
    expect(Nais::Log::Parser.parse_accesslog('127.0.0.1 frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326')).
      to eql([{"remote_ip"=>"127.0.0.1",
               "user"=>"frank",
               "timestamp"=>"2000-10-10T13:55:36-07:00",
               "request"=>"GET /apache_pb.gif HTTP/1.0",
               "response_code"=>"200",
               "content_length"=>"2326"},
              nil])
  end

  it "does parse accesslog with extended data" do
    expect(Nais::Log::Parser.parse_accesslog('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/4.08 [en] (Win98; I ;Nav)"')).
      to eql([{"remote_ip"=>"127.0.0.1",
               "user"=>"frank",
               "timestamp"=>"2000-10-10T13:55:36-07:00",
               "request"=>"GET /apache_pb.gif HTTP/1.0",
               "response_code"=>"200",
               "content_length"=>"2326"},
              " \"http://www.example.com/start.html\" \"Mozilla/4.08 [en] (Win98; I ;Nav)\""])
  end

  it "does return nil on non-glog" do
    expect(Nais::Log::Parser.parse_glog('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse glog" do
    expect(Nais::Log::Parser.parse_glog('E0926 13:36:57.136153       6 reflector.go:201] k8s.io/kube-state-metrics/collectors/persistentvolumeclaim.go:60: Failed to list *v1.PersistentVolumeClaim: User "system:serviceaccount:nais:nais-prometheus-prometheus-kube-state-metrics" cannot list persistentvolumeclaims at the cluster scope. (get persistentvolumeclaims)')).
      to eql({"file" => "reflector.go",
              "level" => "Error",
              "line" => "201",
              "message" => "k8s.io/kube-state-metrics/collectors/persistentvolumeclaim.go:60: Failed to list *v1.PersistentVolumeClaim: User \"system:serviceaccount:nais:nais-prometheus-prometheus-kube-state-metrics\" cannot list persistentvolumeclaims at the cluster scope. (get persistentvolumeclaims)",
              "thread" => "6",
              "timestamp" => Time.now.year.to_s+"-09-26T13:36:57.136153000+02:00"})
  end
  
end
