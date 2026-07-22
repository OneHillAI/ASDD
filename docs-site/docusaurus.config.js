// @ts-check
const {themes} = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'ASDD',
  tagline: 'Agentic Spec-Driven Development',
  url: 'https://onehillai.github.io',
  baseUrl: '/ASDD/',
  organizationName: 'OneHillAI',
  projectName: 'ASDD',
  onBrokenLinks: 'warn',
  markdown: {hooks: {onBrokenMarkdownLinks: 'warn'}},
  i18n: {defaultLocale: 'en', locales: ['en']},
  presets: [
    ['classic', {
      docs: {
        path: '../docs',
        routeBasePath: '/docs',
        sidebarPath: require.resolve('./sidebars.js'),
        exclude: ['**/handoffs/**'],
        editUrl: 'https://github.com/OneHillAI/ASDD/edit/main/docs/',
      },
      blog: false,
      theme: {customCss: require.resolve('./src/css/custom.css')},
    }],
  ],
  themeConfig: {
    navbar: {
      title: 'ASDD',
      items: [
        {type: 'docSidebar', sidebarId: 'main', position: 'left', label: 'Docs'},
        {href: 'https://github.com/OneHillAI/ASDD', label: 'GitHub', position: 'right'},
      ],
    },
    footer: {
      style: 'dark',
      copyright: 'Stewarded by the OneHill Foundation. ASDD is Apache-2.0.',
    },
    prism: {theme: themes.github, darkTheme: themes.dracula},
  },
};
module.exports = config;
