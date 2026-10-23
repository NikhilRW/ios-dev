const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const config = {
  server: {
    enhanceMiddleware: middleware => (req, res, next) => {
      // Caddy + ngrok can produce "http, https", but Metro expects one scheme.
      const forwardedProto = req.headers['x-forwarded-proto'];
      if (typeof forwardedProto === 'string') {
        req.headers['x-forwarded-proto'] = forwardedProto.split(',')[0].trim();
      }
      return middleware(req, res, next);
    },
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
