class DmarcCat < Formula
  desc "Analyze and display DMARC XML reports"
  homepage "https://github.com/keltia/dmarc-cat"
  url "https://github.com/keltia/dmarc-cat/archive/refs/tags/v0.15.0.tar.gz"
  sha256 "886bf33ba60d601de74a1e9d437a8e09eea5c03a05b09c0f685fa02d1c174bba"
  license "BSD-2-Clause"

  livecheck do
    url :stable
  end

  depends_on "go" => :build
  depends_on "gpgme"

  deny_network_access!

  def fetch
    system "go", "mod", "download"
  end

  def install
    ENV["VERSION"] = version

    # Be able to find the `gpgme` headers and libs
    ENV.append "CGO_CFLAGS", "-I#{HOMEBREW_PREFIX}/include"
    ENV.append "CGO_LDFLAGS", "-L#{HOMEBREW_PREFIX}/lib"

    # This test requires live DNS, which is unavailable in the build sandbox.
    system "go", "test", "-v", "-skip", "^TestRealResolver_LookupAddr$", "."
    system "make", "all"

    bin.install "dmarc-cat"
  end

  test do
    report = testpath/"example.net!example.com!0!86400.xml"
    report.write <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feedback>
        <report_metadata>
          <org_name>example.net</org_name>
          <email>dmarc@example.net</email>
          <report_id>1</report_id>
          <date_range><begin>0</begin><end>86400</end></date_range>
        </report_metadata>
        <policy_published>
          <domain>example.com</domain>
          <adkim>r</adkim><aspf>r</aspf><p>none</p><pct>100</pct>
        </policy_published>
        <record>
          <row>
            <source_ip>192.0.2.1</source_ip><count>3</count>
            <policy_evaluated>
              <disposition>none</disposition><dkim>pass</dkim><spf>pass</spf>
            </policy_evaluated>
          </row>
          <identifiers><header_from>example.com</header_from></identifiers>
          <auth_results>
            <dkim><domain>example.com</domain><result>pass</result></dkim>
            <spf><domain>example.com</domain><result>pass</result></spf>
          </auth_results>
        </record>
      </feedback>
    XML
    assert_match(/^192\.0\.2\.1\s+3\s+example\.com\s+example\.com\s+pass\s+pass\s*$/,
                 shell_output("#{bin}/dmarc-cat -N #{report}"))
  end
end
