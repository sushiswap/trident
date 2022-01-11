const config = require('@sushiswap/prettier-config')

module.exports = {
  ...config.default,
  overrides: [
    {
      files: '*.sol',
      options: {
        printWidth: 140,
        tabWidth: 4,
        singleQuote: false,
        bracketSpacing: false,
        explicitTypes: 'always',
        endOfLine: 'lf',
      },
    },
  ],
}
