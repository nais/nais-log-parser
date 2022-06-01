# coding: utf-8
require "time"
require "spec_helper"

ENV['TZ']='UTC'

RSpec.describe Nais::Log::Parser do
  it "has a version number" do
    expect(Nais::Log::Parser::VERSION).not_to be nil
  end

  it "does convert array elements to string" do
    expect(Nais::Log::Parser.string_array(["a", 2, {"foo": "bar"}, ["a", 'b', "c"]])).
      to eql(['a', '2', '{:foo=>"bar"}', '["a", "b", "c"]'])
  end

  it "does flatten hash" do
    expect(Nais::Log::Parser.flatten_hash({"a"=>"b", "c.c"=>"d", "e"=>{"f"=>"g"}, "h"=>{"i"=>"j", "k"=>{"l.l"=>"m"}}})).
      to eql({"a"=>"b", "c_c"=>"d", "e_f"=>"g", "h_i"=>"j", "h_k_l_l"=>"m"})
  end

  it "does not flatten specified field in hash" do
    expect(Nais::Log::Parser.flatten_hash({"a"=>"b", "c.c"=>"d", "e"=>{"f"=>"g"}, "h"=>{"i"=>"j", "k"=>{"l.l"=>"m"}}}, "", /^e$/)).
      to eql({"a"=>"b", "c_c"=>"d", "e"=>{"f" => "g"}, "h_i"=>"j", "h_k_l_l"=>"m"})
  end

  it "does flatten hash with array elements" do
    expect(Nais::Log::Parser.flatten_hash({"a"=>"b", "c"=>{"d"=>["e", 7]}})).
      to eql({"a"=>"b", "c_d"=>["e", "7"]})
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

  it "does rename level field if not string (loglevel)" do
    r = {'thread_name'=>'thread_name','logger_name'=>'logger_name','level'=>42,'level_value'=>10000}
    expect(Nais::Log::Parser.remap_java_fields(r)).
      to eql({'thread'=>'thread_name', 'component'=>'logger_name', 'x_level'=>42})
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

  it "does return nil on non coredns log" do
    expect(Nais::Log::Parser.parse_coredns('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse coredns log" do
    expect(Nais::Log::Parser.parse_coredns('[INFO] CoreDNS-1.3.0')).
      to eql({"level" => "INFO",
              "message" => "CoreDNS-1.3.0"})
  end

  it "does parse coredns access log" do
    expect(Nais::Log::Parser.parse_coredns('[INFO] [::1]:50759 - 29008 "A IN example.org. udp 41 false 4096" NOERROR qr,rd,ra,ad 68 0.037990251s')).
      to eql({"level" => "INFO",
              "remote_ip" => "[::1]",
              "remote_port" => "50759",
              "query_id" => "29008",
              "message" => "A IN example.org. udp 41 false 4096",
              "response_code" => "NOERROR",
              "flags" => ["qr","rd","ra","ad"],
              "content_length" => "68",
              "processing_time" => "0.037990251"})
  end

  it "does return nil on non rook log" do
    expect(Nais::Log::Parser.parse_rook('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse rook log" do
    expect(Nais::Log::Parser.parse_rook('2019-01-09 07:17:30.267249 I | exec: Running command: ceph osd dump --cluster=rook --conf=/var/lib/rook/rook/rook.config --keyring=/var/lib/rook/rook/client.admin.keyring --format json --out-file /tmp/707633009')).
      to eql({"component"=>"exec",
              "timestamp"=>"2019-01-09T07:17:30.267249000Z",
              "level"=>"Info",
              "message"=>"Running command: ceph osd dump --cluster=rook --conf=/var/lib/rook/rook/rook.config --keyring=/var/lib/rook/rook/client.admin.keyring --format json --out-file /tmp/707633009"})
  end

  it "does return nil on non redis log" do
    expect(Nais::Log::Parser.parse_redis('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse redis2 log" do
    expect(Nais::Log::Parser.parse_redis('[4018] 14 Nov 07:01:22.119 * Background saving terminated with success')).
      to eql({"thread"=>"4018",
              "timestamp"=>Time.new.year.to_s+"-11-14T07:01:22.119Z",
              "level"=>"Info",
              "message"=>"Background saving terminated with success"})
  end

  it "does parse redis3 log" do
    expect(Nais::Log::Parser.parse_redis('1:S 10 Aug 08:56:10.311 # Error condition on socket for SYNC: Connection refused')).
      to eql({"thread"=>"1",
              "timestamp"=>Time.new.year.to_s+"-08-10T08:56:10.311Z",
              "level"=>"Error",
              "component"=>"slave",
              "message"=>"Error condition on socket for SYNC: Connection refused"})
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

  it "does parse accesslog without ip" do
    expect(Nais::Log::Parser.parse_accesslog('- - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326')).
      to eql([{"user"=>"frank",
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

  it "does parse nginx ingress controller accesslog" do
    expect(Nais::Log::Parser.parse_accesslog_nginx_ingress('127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "-" "foobar" 126 0.019 [istio-system-gw-nais-io-443] [] 10.7.72.36:8443 0 0.019 304 364f3a5a8c0fd06ddf73d535bde1c8c6')).
      to eql({"remote_ip"=>"127.0.0.1",
              "timestamp"=>"2000-10-10T13:55:36-07:00",
              "request"=>"GET /apache_pb.gif HTTP/1.0",
              "response_code"=>"200",
              "content_length"=>"2326",
              "user_agent" => "foobar",
              "request_id" => "364f3a5a8c0fd06ddf73d535bde1c8c6",
              "request_length" => "126",
              "request_time" => "0.019",
              "upstream_address" => "10.7.72.36:8443",
              "upstream_name" => "istio-system-gw-nais-io-443",
              "upstream_response_length" => "0",
              "upstream_response_time" => "0.019",
              "upstream_status" => "304"
             })
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
              "timestamp" => Time.now.year.to_s+"-09-26T13:36:57.136153000Z"})
  end

  it "does return nil on non-simple log" do
    expect(Nais::Log::Parser.parse_simple('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse simple log" do
    expect(Nais::Log::Parser.parse_simple('2018-07-31T12:56:12.828 INFO [main] org.apache.catalina.startup.Catalina.start Server startup in 59702 ms')).
      to eql({"level" => "INFO",
              "thread" => "main",
              "message" => "Server startup in 59702 ms",
              "component" => "org.apache.catalina.startup.Catalina.start",
              "timestamp" => '2018-07-31T12:56:12.828000000Z'})
  end

  it "does parse simple log without thread" do
    expect(Nais::Log::Parser.parse_simple('2018-07-31T12:56:12,828 INFO org.apache.catalina.startup.Catalina.start Server startup in 59702 ms')).
      to eql({"level" => "INFO",
              "message" => "Server startup in 59702 ms",
              "component" => "org.apache.catalina.startup.Catalina.start",
              "timestamp" => '2018-07-31T12:56:12.828000000Z'})
  end

  it "does parse simple log without millisecond timestamp" do
    expect(Nais::Log::Parser.parse_simple('2018-07-31 12:56:12 INFO [foo.bar] org.apache.catalina.startup.Catalina.start Server startup in 59702 ms')).
      to eql({"level" => "INFO",
              "thread" => "foo.bar",
              "message" => "Server startup in 59702 ms",
              "component" => "org.apache.catalina.startup.Catalina.start",
              "timestamp" => '2018-07-31T12:56:12.000000000Z'})
  end

  it "does return nil on non-capnslog" do
    expect(Nais::Log::Parser.parse_capnslog('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does parse capnslog" do
    expect(Nais::Log::Parser.parse_capnslog('2017-11-22 17:06:45.734626 I | op-k8sutil: cluster role rook-agent already exists. Updating if needed.')).
      to eql({"level" => "Info",
              "component" => "op-k8sutil",
              "message" => "cluster role rook-agent already exists. Updating if needed.",
              "timestamp" => "2017-11-22T17:06:45.734626000Z"})
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
      to eql({'component'=>'plugin', 'level'=>'Debug', 'message'=>'foo bar', 'timestamp'=>'2017-10-02T10:31:38.939550638Z'})
  end

  it "does nothing when missing json field" do
    r = {'log'=>"{\"message\":\"test\",\"foo\":\"bar\"}\n",'stream'=>'stdout','time'=>'2018-05-23T07:56:09.330928186Z'}
    expect(Nais::Log::Parser.merge_json_field(r, 'missing')).to eql(r)
  end

  it "does nothing on json parse error" do
    r = {'log'=>"{\"message\":\"test\",\"foo\"=\"bar\"}\n",'stream'=>'stdout','time'=>'2018-05-23T07:56:09.330928186Z'}
    expect(Nais::Log::Parser.merge_json_field(r, 'log')).to eql(r)
  end

  it "does nothing on non-json field" do
    r = {'log'=>"Lorem ipsum dolor sit amet, consectetur adipiscing elit",'stream'=>'stdout','time'=>'2018-05-23T07:56:09.330928186Z'}
    expect(Nais::Log::Parser.merge_json_field(r, 'log')).to eql(r)
  end

  it "does merge json" do
    r = {'log'=>"{\"message\":\"test\",\"foo\":\"bar\",\"array\": [\"a\", \"b\"], \"hash\": {\"a\": 1}}\n",'stream'=>'stdout','time'=>'2018-05-23T07:56:09.330928186Z'}
    expect(Nais::Log::Parser.merge_json_field(r, 'log')).
      to eql({'stream'=>'stdout', 'foo'=>'bar', 'array'=>['a', 'b'], 'hash'=>{'a'=>1}, 'message'=>'test', 'time'=>'2018-05-23T07:56:09.330928186Z'})
  end

  it "does return nil on non logrus" do
    expect(Nais::Log::Parser.parse_logrus('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does return nil on valid logfmt but non logrus" do
    expect(Nais::Log::Parser.parse_logrus('foo=bar a=14 baz="hello kitty"')).
      to be nil
  end

  it "does parse logrus" do
    expect(Nais::Log::Parser.parse_logrus('time="2018-05-24T07:11:18Z" level=info msg="deployment updated" deployment=rfs-dpl namespace=x8 service=k8s.deployment src="deployment.go:77"')).
      to eql({"time" => "2018-05-24T07:11:18Z",
              "level" => "info",
              "msg" => "deployment updated",
              "deployment" => "rfs-dpl",
              "namespace" => "x8",
              "service" => "k8s.deployment",
              "src" => "deployment.go:77"})
  end

  it "does return nil on non go-kit" do
    expect(Nais::Log::Parser.parse_gokit('Lorem ipsum dolor sit amet, consectetur adipiscing elit.')).
      to be nil
  end

  it "does return nil on valid logfmt but non go-kit" do
    expect(Nais::Log::Parser.parse_gokit('foo=bar a=14 baz="hello kitty"')).
      to be nil
  end

  it "does parse go-kit" do
    expect(Nais::Log::Parser.parse_gokit('level=warn ts=2018-05-31T12:04:08.86715797Z caller=scrape.go:697 component="scrape manager" scrape_pool=kubernetes-pods target=http://192.168.60.30:8080/foobar/internal/metric msg="append failed" err="no token found"')).
      to eql({"ts" => "2018-05-31T12:04:08.86715797Z",
              "level" => "warn",
              "msg" => "append failed",
              "caller" => "scrape.go:697",
              "component" => "scrape manager",
              "scrape_pool" => "kubernetes-pods",
              "target" => "http://192.168.60.30:8080/foobar/internal/metric",
              "err" => "no token found"})
  end

  it "does parse go-kit error without message" do
    expect(Nais::Log::Parser.parse_gokit('level=error ts=2018-08-09T09:02:36.303114134Z caller=main.go:218 component=k8s_client_runtime err="github.com/prometheus/prometheus/discovery/kubernetes/kubernetes.go:325: Failed to list *v1.Service: Get https://10.42.42.42:443/api/v1/services?resourceVersion=0: dial tcp 10.254.0.1:443: connect: connection refused"')).
      to eql({"ts" => "2018-08-09T09:02:36.303114134Z",
              "level" => "error",
              "err" => "github.com/prometheus/prometheus/discovery/kubernetes/kubernetes.go:325: Failed to list *v1.Service: Get https://10.42.42.42:443/api/v1/services?resourceVersion=0: dial tcp 10.254.0.1:443: connect: connection refused",
              "caller" => "main.go:218",
              "component" => "k8s_client_runtime"})
  end

  it "does decode uri without query string" do
    expect(Nais::Log::Parser.parse_uri('/foobar/zot/%41%42%43')).
      to eql({"path" => "/foobar/zot/ABC"})
  end

  it "does decode uri with empty query string" do
    expect(Nais::Log::Parser.parse_uri('/foobar/zot/%41%42%43?')).
      to eql({"path" => "/foobar/zot/ABC"})
  end

  it "does decode uri with query string" do
    expect(Nais::Log::Parser.parse_uri('/foobar/zot/%41%42%43?foo=bar&zot&array=a+1&array=b%202')).
      to eql({"path" => "/foobar/zot/ABC",
              "query_params" => {"foo" => "bar", "array" => ["a 1", "b 2"]}})
  end

  it "does remap journald fields" do
    r = {"boot_id"=>"7b518c56a14341c7b5dc82a149d934cc", "priority"=>"6", "syslog_facility"=>"3", "uid"=>"0", "gid"=>"0", "systemd_slice"=>"system.slice", "cap_effective"=>"3fffffffff", "transport"=>"stdout", "machine_id"=>"6708382564e845f1a790c230136de8b3", "hostname"=>"e34apvl00685.devillo.no", "selinux_context"=>"system_u:system_r:kernel_t:s0", "stream_id"=>"4ff13712ce9e40b299a340a4224a30c3", "syslog_identifier"=>"update_engine", "pid"=>"703", "comm"=>"update_engine", "exe"=>"/usr/sbin/update_engine", "cmdline"=>"/usr/sbin/update_engine -foreground -logtostderr", "systemd_cgroup"=>"/system.slice/update-engine.service", "systemd_unit"=>"update-engine.service", "systemd_invocation_id"=>"47ed25ee8e904f268cde9c58d71a3e68", "message"=>"I0117 14:30:46.485997   703 action_processor.cc:73] ActionProcessor::ActionComplete: finished last action of type OmahaRequestAction","source_realtime_timestamp"=>"1548155111168093"}
    expect(Nais::Log::Parser.remap_journald_fields(r)).
      to eql({'facility'=>'daemon','level'=>'Info', 'uid'=>'0', 'gid'=>'0', 'category'=>'stdout','host'=>'e34apvl00685.devillo.no','program'=>'update_engine','pid'=>'703','command'=>'update_engine','message'=>'I0117 14:30:46.485997   703 action_processor.cc:73] ActionProcessor::ActionComplete: finished last action of type OmahaRequestAction','timestamp'=>'2019-01-22T11:05:11.168093Z'})
  end

  it "does remap elasticsearch fields" do
    t = Time.now
    r = {"@timestamp"=>"2019-04-10 13:54:19,441", "level"=>"Info", "log"=>"Lorem ipsum dolor sit amet, consectetur adipiscing elit"}
    expect(Nais::Log::Parser.remap_elasticsearch_fields(t, r).tap { |hs| hs.delete("received_at") }).
      to eql({'@timestamp'=>'2019-04-10T13:54:19.441000000+00:00', 'level'=>'Info', 'message'=>'Lorem ipsum dolor sit amet, consectetur adipiscing elit'})
  end

  it "does remap elasticsearch fields on record with timestamp and timezone" do
    t = Time.now
    r = {"@timestamp"=>"2019-04-11T10:06:53.389+02:00", "level"=>"Info", "log"=>"Lorem ipsum dolor sit amet, consectetur adipiscing elit"}
    expect(Nais::Log::Parser.remap_elasticsearch_fields(t, r).tap { |hs| hs.delete("received_at") }).
      to eql({'@timestamp'=>'2019-04-11T10:06:53.389000000+02:00', 'level'=>'Info', 'message'=>'Lorem ipsum dolor sit amet, consectetur adipiscing elit'})
  end

  it "does remap elasticsearch fields on record without timestamp" do
    t = Time.now
    r = {"level"=>"Info", "log"=>"Lorem ipsum dolor sit amet, consectetur adipiscing elit"}
    expect(Nais::Log::Parser.remap_elasticsearch_fields(t, r).tap { |hs| hs.delete("received_at") }).
      to eql({'@timestamp'=>t.iso8601(9), 'level'=>'Info', 'message'=>'Lorem ipsum dolor sit amet, consectetur adipiscing elit'})
  end

  it "does remap elasticsearch fields on record with illegal timestamp" do
    t = Time.now
    r = {"@timestamp"=>"foo", "level"=>"Info", "log"=>"Lorem ipsum dolor sit amet, consectetur adipiscing elit"}
    expect(Nais::Log::Parser.remap_elasticsearch_fields(t, r).tap { |hs| hs.delete("received_at") }).
      to eql({'@timestamp'=>t.iso8601(9), 'unparsed_timestamp'=>'foo', 'level'=>'Info', 'message'=>'Lorem ipsum dolor sit amet, consectetur adipiscing elit'})
  end

  it "does remap elasticsearch fields on record with numeric timestamp" do
    t = Time.at(1636007022.2)
    r = {"ts"=>t.to_f, "level"=>"Info", "log"=>"Lorem ipsum dolor sit amet, consectetur adipiscing elit"}
    expect(Nais::Log::Parser.remap_elasticsearch_fields(t, r).tap { |hs| hs.delete("received_at") }).
      to eql({'@timestamp'=>'2021-11-04T06:23:42.200000+00:00', 'level'=>'Info', 'message'=>'Lorem ipsum dolor sit amet, consectetur adipiscing elit'})
  end

  it "does jupyter logs parse" do
    logged = '[W 2021-03-16 16:05:29.163 SingleUserNotebookApp handlers:252] Replacing stale connection: ead00266-1e94-47e3-9fc3-f1f78c39f0e0:2087e0bf-2bc8-4e39-9cd5-7591b7fb8aa4'
    expect(Nais::Log::Parser.parse_jupyterhub_notebook(logged)).
      to eql({"component" => "SingleUserNotebookApp", "file" => "handlers", "level" => "Warning", "line" => "252", "message" => "Replacing stale connection: ead00266-1e94-47e3-9fc3-f1f78c39f0e0:2087e0bf-2bc8-4e39-9cd5-7591b7fb8aa4", "timestamp" => "2021-03-16T16:05:29+00:00",})
  end
end
