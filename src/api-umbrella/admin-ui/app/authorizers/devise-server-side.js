import Base from 'ember-simple-auth/authorizers/base';

export default Base.extend({
  authorize(data, callback) {
    callback(data.api_key, data.csrf_token);
  },
});
