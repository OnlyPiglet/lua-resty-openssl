# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);


my $pwd = cwd();

my $use_luacov = $ENV{'TEST_NGINX_USE_LUACOV'} // '';

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/lib/?/init.lua;;";
    init_by_lua_block {
        if "1" == "$use_luacov" then
            require 'luacov.tick'
            jit.off()
        end
    }
};

no_long_string();

run_tests();

__DATA__
=== TEST 1: Generates RSA key by default
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local p = require("resty.openssl.pkey").new()
            ngx.say(p:to_PEM('private'))
        }
    }
--- request
    GET /t
--- response_body_like eval
"-----BEGIN PRIVATE KEY-----"
--- no_error_log
[error]

=== TEST 2: Generates RSA key explictly
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local p = require("resty.openssl.pkey").new({
                type = 'RSA',
                bits = 2048,
            })
            ngx.say(p:to_PEM('private'))
        }
    }
--- request
    GET /t
--- response_body_like eval
"-----BEGIN PRIVATE KEY-----"
--- no_error_log
[error]

=== TEST 3: Generates EC key
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local p = require("resty.openssl.pkey").new({
                type = 'EC',
                curve = 'prime256v1',
            })
            ngx.say(p:to_PEM('private'))
        }
    }
--- request
    GET /t
--- response_body_like eval
"-----BEGIN PRIVATE KEY-----"
--- no_error_log
[error]

=== TEST 4: Rejects invalid arg
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local pkey = require("resty.openssl.pkey")
            local p, err = pkey.new(123)
            ngx.say(err)
            local p, err = pkey.new('PRIVATE KEY')
            ngx.say(err)
        }
    }
--- request
    GET /t
--- response_body_like eval
"unexpected type.+
pkey.new:load_pkey: .+
"
--- no_error_log
[error]

=== TEST 5: Loads PEM format
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local pkey = require("resty.openssl.pkey")
            local p1, err = pkey.new()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            local p2, err = pkey.new(p1:to_PEM('private'))
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.print(p1:to_PEM('private') == p2:to_PEM('private'))
        }
    }
--- request
    GET /t
--- response_body eval
"true"
--- no_error_log
[error]

=== TEST 6: Loads DER format
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local pkey = require("resty.openssl.pkey")
            local p1, err = pkey.new()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            local pem = p1:to_PEM('private')
            local der, err = require("ngx.ssl").priv_key_pem_to_der(pem)
            local p2, err = pkey.new(der)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.print(p2 and pem == p2:to_PEM('private'))
        }
    }
--- request
    GET /t
--- response_body eval
"true"
--- no_error_log
[error]

=== TEST 7: Extracts parameters
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local p, err = require("resty.openssl.pkey").new({
                exp = 65537,
            })
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            local params, err = p:get_parameters()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(params.d ~= nil)
            ngx.say(params.e ~= nil)
            ngx.say(params.n ~= nil)
            local b, err = params.e:to_number()
            if err then
                ngx.log(ngx.ERR, err)
            end
            ngx.say(b)
        }
    }
--- request
    GET /t
--- response_body eval
"true
true
true
65537
"
--- no_error_log
[error]

=== TEST 8: Sign and verify
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local p, err = require("resty.openssl.pkey").new()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            
            local digest, err = require("resty.openssl.digest").new("SHA256")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            local _, err = digest:update("🕶️", "+1s")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            local s, err = p:sign(digest)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(#s)
            local v, err = p:verify(s, digest)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(v)
        }
    }
--- request
    GET /t
--- response_body eval
"256
true
"
--- no_error_log
[error]

=== TEST 9: Error on bad digest or verify parameters
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local p, err = require("resty.openssl.pkey").new()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local s, err = p:sign("not a cdata")
            ngx.say(err)
            local v, err = p:verify(s, "not a cdata")
            ngx.say(err)
        }
    }
--- request
    GET /t
--- response_body eval
"expect a digest instance at #1
expect a digest instance at #2
"
--- no_error_log
[error]

=== TEST 10: Outputs public key
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local p, err = require("resty.openssl.pkey").new()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(p:to_PEM())
        }
    }
--- request
    GET /t
--- response_body_like eval
"-----BEGIN PUBLIC KEY-----"
--- no_error_log
[error]

=== TEST 11: Encrypt and decrypt
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local privkey, err = require("resty.openssl.pkey").new()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            local pubkey, err = require("resty.openssl.pkey").new(assert(privkey:to_PEM("public")))
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local s, err = pubkey:encrypt("23333")
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(#s)
            local decrypted, err = privkey:decrypt(s)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say(decrypted)
        }
    }
--- request
    GET /t
--- response_body eval
"256
23333
"
--- no_error_log
[error]


=== TEST 12: Loads encrypted PEM pkey with passphrase
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local f = io.open("t/fixtures/ec_key_encrypted.pem"):read("*a")
            local privkey, err = require("resty.openssl.pkey").new(f, {
                format = "PEM",
                type = "pr",
                passphrase = "wrongpasswrod",
            })
            ngx.say(err)
            local privkey, err = require("resty.openssl.pkey").new(f, {
                format = "PEM",
                type = "pr",
                passphrase = "123456",
            })
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("ok")
        }
    }
--- request
    GET /t
--- response_body_like eval
"pkey.new.+bad decrypt
ok
"
--- no_error_log
[error]


=== TEST 13: Loads encrypted PEM pkey with passphrase callback
--- http_config eval: $::HttpConfig
--- config
    location =/t {
        content_by_lua_block {
            local f = io.open("t/fixtures/ec_key_encrypted.pem"):read("*a")
            local privkey, err = require("resty.openssl.pkey").new(f, {
                format = "PEM",
                type = "pr",
                passphrase_cb = function()
                    return "wrongpassword"
                end,
            })
            ngx.say(err)
            local privkey, err = require("resty.openssl.pkey").new(f, {
                format = "PEM",
                type = "pr",
                passphrase_cb = function()
                    return "123456"
                end,
            })
            if err then
                ngx.log(ngx.ERR, err)
                return
            end
            ngx.say("ok")
        }
    }
--- request
    GET /t
--- response_body_like eval
"pkey.new.+bad decrypt
ok
"
--- no_error_log
[error]