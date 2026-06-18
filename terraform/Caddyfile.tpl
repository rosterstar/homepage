(security_headers) {
    header {
        X-Frame-Options "DENY"
        Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline';"
        X-Content-Type-Options "nosniff"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }
}

${domain_name}, www.${domain_name} {
    reverse_proxy app:8080
    import security_headers
}

grafana.${domain_name} {
    reverse_proxy grafana:3000
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }
}

prometheus.${domain_name} {
    basic_auth {
        admin ${prometheus_password_hash}
    }
    reverse_proxy prometheus:9090
    import security_headers
}
