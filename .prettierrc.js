const config = require('@sushiswap/prettier-config')

module.exports = {
  ...config.default,
  singleQuote: false,
  semi: true,
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
