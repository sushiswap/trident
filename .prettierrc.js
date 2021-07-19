module.exports = {
    ...require("@sushiswap/prettier-config"),
    // TODO: If a non-default solidity config is needed, we could add this to our
    // config repo and import as @sushiswap/prettier-config/solidity. Also, feel
    // free to add to the default config which is required above.
    overrides: [
        {
            files: ["contracts/**/*.sol"],
            options: {
                printWidth: 130,
                tabWidth: 4,
                useTabs: false,
                singleQuote: false,
                bracketSpacing: false,
                explicitTypes: "always",
            },
        },
        {
            files: ["**/*.js"],
            options: {
                printWidth: 120,
                tabWidth: 4,
                useTabs: false,
                singleQuote: false,
                bracketSpacing: true,
                arrowParens: "avoid",
                explicitTypes: "always",
            },
        },
    ],
};
