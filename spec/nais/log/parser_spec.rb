# coding: utf-8
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
    expect(Nais::Log::Parser.get_keywords('Lorem ipsum dolor sit amet, consectetur adipiscing elit.', /\b[A-Z]\w+Exception\b/)).
      to be nil
  end

  it "does find single exception" do
    expect(Nais::Log::Parser.get_keywords('Exception in thread "main" java.util.NoSuchElementException: foo bar', /\b[A-Z]\w+Exception\b/)).
      to eql('NoSuchElementException')
  end

  it "does remove duplicate exception" do
    expect(Nais::Log::Parser.get_keywords('Exception in thread "main" java.util.NoSuchElementException: NoSuchElementException', /\b[A-Z]\w+Exception\b/)).
      to eql('NoSuchElementException')
  end

  it "does find multiple exceptions" do
    expect(Nais::Log::Parser.get_keywords("org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'requestMappingHandlerMapping' defined in class org.springframework.web.servlet.config.annotation.DelegatingWebMvcConfiguration: Invocation of init method failed; nested exception is java.lang.IllegalStateException: Ambiguous mapping found. Cannot map 'appController' bean method", /\b[A-Z]\w+Exception\b/)).
      to eql(['BeanCreationException', 'IllegalStateException'])
  end

  it "does find oracle error code" do
    expect(Nais::Log::Parser.get_keywords('org.hibernate.engine.jdbc.spi.SqlExceptionHelper ORA-00001: unique constraint (FOO.BAR) violated', /\bORA-\d{5}\b/)).
      to eql('ORA-00001')
  end

  it "does prefix fields" do
    expect(Nais::Log::Parser.prefix_fields({'a'=>'ok', 'b'=>'ok', 'c'=>'ok', 'aa'=>'prefix', 'ba'=>'prefix', 'foo'=>'prefix'}, 'x_', /^(?!(?:a$|b$|c$)).*/)).
      to eql({'a'=>'ok', 'b'=>'ok', 'c'=>'ok', 'x_aa'=>'prefix', 'x_ba'=>'prefix', 'x_foo'=>'prefix'})
  end

  it "does prefix fields with negated regex" do
    expect(Nais::Log::Parser.prefix_fields({'a'=>'ok', 'b'=>'ok', 'c'=>'ok', 'aa'=>'prefix', 'ba'=>'prefix', 'foo'=>'prefix'}, 'x_', /^(a|b|c)$/, true)).
      to eql({'a'=>'ok', 'b'=>'ok', 'c'=>'ok', 'x_aa'=>'prefix', 'x_ba'=>'prefix', 'x_foo'=>'prefix'})
  end

  it "doesn't find any kv pairs" do
    expect(Nais::Log::Parser.parse_kv("foo bar= zot=")).
      to be nil
  end

  it "does drop long key match in kv pairs" do
    expect(Nais::Log::Parser.parse_kv("foofoofoofoofoofoofoofoofoofoofoo=bar")).
      to be nil
  end

  it "does find kv pairs" do
    expect(Nais::Log::Parser.parse_kv('Lorem ipsum dolor sit amet, consectetur adipiscing elit. foo=bar, zot="hello world" empty=""')).
      to eql({'foo'=>'bar', 'zot'=>'hello world'})
  end

  it "does remap java fields" do
    r = {'thread_name'=>'thread_name','logger_name'=>'logger_name','level'=>'LEVEL','level_value'=>10000}
    expect(Nais::Log::Parser.remap_java_fields(r)).
      to eql({'thread'=>'thread_name', 'component'=>'logger_name', 'level'=>'Level'})
  end

  it "does remap log4j2 logs" do
    r = { "exception" => { "exception_class" => "java.lang.InterruptedException",
                           "exception_message" => "foobar",
                           "stacktrace" => "java.lang.InterruptedException: foobar\n\tat LoggerTest.rndException(LoggerTest.java:35)\n\tat LoggerTest.main(LoggerTest.java:20)\n"
                         },
          "mdc" => {
            "mdc1" => "val1",
            "mdc2" => "val2",
          },
          "@version" => 1,
          "source_host" => "04bd2b402f37",
          "message" => "gwfuwgqeotszxojcywbohrxdaghw",
          "thread_name" => "main",
          "@timestamp" => "2017-11-13T09:47:52.370+00:00",
          "level" => "ERROR",
          "logger_name" => "LoggerTest"
        }
    expect(Nais::Log::Parser.remap_java_fields(r)).
      to eql({"@timestamp" => "2017-11-13T09:47:52.370+00:00",
              "@version" => 1,
              "message" => "gwfuwgqeotszxojcywbohrxdaghw",
              "level" => "Error",
              "component" => "LoggerTest",
              "thread" => "main",
              "stack_trace" => "java.lang.InterruptedException: foobar\n\tat LoggerTest.rndException(LoggerTest.java:35)\n\tat LoggerTest.main(LoggerTest.java:20)\n",
              "mdc1" => "val1",
              "mdc2" => "val2"
             });
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

  it "does handle accesslog without processing time" do
    expect(Nais::Log::Parser.parse_accesslog_with_processing_time('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326')).
      to eql({"remote_ip"=>"127.0.0.1",
              "user"=>"frank",
              "timestamp"=>"2000-10-10T13:55:36-07:00",
              "request"=>"GET /apache_pb.gif HTTP/1.0",
              "response_code"=>"200",
              "content_length"=>"2326"})
  end

  it "does handle accesslog with - as processing time" do
    expect(Nais::Log::Parser.parse_accesslog_with_processing_time('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 -')).
      to eql({"remote_ip"=>"127.0.0.1",
              "user"=>"frank",
              "timestamp"=>"2000-10-10T13:55:36-07:00",
              "request"=>"GET /apache_pb.gif HTTP/1.0",
              "response_code"=>"200",
              "content_length"=>"2326"})
  end

  it "does parse accesslog with processing time" do
    expect(Nais::Log::Parser.parse_accesslog_with_processing_time('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 150.806µs')).
      to eql({"remote_ip"=>"127.0.0.1",
              "user"=>"frank",
              "timestamp"=>"2000-10-10T13:55:36-07:00",
              "request"=>"GET /apache_pb.gif HTTP/1.0",
              "response_code"=>"200",
              "content_length"=>"2326",
              "processing_time"=>"150.806"})
  end

  it "does handle accesslog without referer and user agent" do
    expect(Nais::Log::Parser.parse_accesslog_with_referer_useragent('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326')).
      to eql({"remote_ip"=>"127.0.0.1",
              "user"=>"frank",
              "timestamp"=>"2000-10-10T13:55:36-07:00",
              "request"=>"GET /apache_pb.gif HTTP/1.0",
              "response_code"=>"200",
              "content_length"=>"2326"})
  end

  it "does handle accesslog with - as user agent" do
    expect(Nais::Log::Parser.parse_accesslog_with_referer_useragent('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://127.0.0.1/" "-"')).
      to eql({"remote_ip"=>"127.0.0.1",
              "user"=>"frank",
              "timestamp"=>"2000-10-10T13:55:36-07:00",
              "request"=>"GET /apache_pb.gif HTTP/1.0",
              "response_code"=>"200",
              "content_length"=>"2326",
              "referer" => "http://127.0.0.1/"})
  end

  it "does parse accesslog with referer and user agent" do
    expect(Nais::Log::Parser.parse_accesslog_with_referer_useragent('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://127.0.0.1/" "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"')).
      to eql({"remote_ip"=>"127.0.0.1",
              "user"=>"frank",
              "timestamp"=>"2000-10-10T13:55:36-07:00",
              "request"=>"GET /apache_pb.gif HTTP/1.0",
              "response_code"=>"200",
              "content_length"=>"2326",
              "referer" => "http://127.0.0.1/",
              "user_agent" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"})
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

  it "does return nil on capnslog" do
    expect(Nais::Log::Parser.parse_capnslog('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse capnslog" do
    expect(Nais::Log::Parser.parse_capnslog('2017-11-22 17:06:45.734626 I | op-k8sutil: cluster role rook-agent already exists. Updating if needed.')).
      to eql({"level" => "Info",
              "component" => "op-k8sutil",
              "message" => "cluster role rook-agent already exists. Updating if needed.",
              "timestamp" => "2017-11-22T17:06:45.734626000+01:00"})
  end

  it "does return nil on non-influxdb log" do
    expect(Nais::Log::Parser.parse_influxdb('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does handle non-accesslog from influxdb httpd log" do
    expect(Nais::Log::Parser.parse_influxdb('[httpd] Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to eql({'component'=>'httpd', 'message'=>'Lorem ipsum dolor sit amet, consectetur adipiscing elit.'})
  end

  it "does handle non-accesslog with timestamp from influxdb httpd log" do
    expect(Nais::Log::Parser.parse_influxdb('[httpd] 2017/10/05 13:08:11 Starting HTTP service')).
      to eql({'component'=>'httpd', 'timestamp'=>'2017-10-05T13:08:11+00:00', 'message'=>'Starting HTTP service'})
  end

  it "does parse loglevel and timestamp from influxdb log" do
    expect(Nais::Log::Parser.parse_influxdb('[I] 2017-10-05T13:08:11Z retention policy shard deletion check commencing service=retention')).
      to eql({'level'=>'Info', 'timestamp'=>'2017-10-05T13:08:11+00:00', 'message'=>'retention policy shard deletion check commencing service=retention'})
  end

  it "does parse influxdb accesslog" do
    expect(Nais::Log::Parser.parse_influxdb('[httpd] 192.168.100.0 - root [28/Sep/2017:09:23:05 +0000] "POST /write?consistency=&db=k8s&precision=&rp=default HTTP/1.1" 204 0 "-" "heapster/v1.4.2" a1fe620e-a42e-11e7-8083-000000000000 37327')).
      to eql({"component"=>"httpd",
              "remote_ip"=>"192.168.100.0",
              "user"=>"root",
              "timestamp"=>"2017-09-28T09:23:05+00:00",
              "message"=>"POST /write?consistency=&db=k8s&precision=&rp=default HTTP/1.1",
              "response_code"=>"204",
              "content_length"=>"0",
              "user_agent"=>"heapster/v1.4.2",
              "request"=>"a1fe620e-a42e-11e7-8083-000000000000",
              "processing_time"=>"37327"})
  end

  it "does parse influxdb non-accesslog" do
    expect(Nais::Log::Parser.parse_influxdb('[tsm1] 2017/09/28 05:53:06 compacting level 2 group (0) /data/data/k8s/default/33/000000008-000000002.tsm (#1)')).
      to eql({"component"=>"tsm1",
              "timestamp"=>"2017-09-28T05:53:06+00:00",
              'message'=>'compacting level 2 group (0) /data/data/k8s/default/33/000000008-000000002.tsm (#1)'})
  end

  it "does remap log15 fields" do
    r = {'logger'=>'plugin','t'=>'2017-10-02T10:31:38.939550638Z','lvl'=>'dbug','msg'=>'foo bar'}
    expect(Nais::Log::Parser.remap_log15(r)).
      to eql({'component'=>'plugin', 'level'=>'Debug', 'message'=>'foo bar', '@timestamp'=>'2017-10-02T10:31:38.939550638Z'})
  end

end
