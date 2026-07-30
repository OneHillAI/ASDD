/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  main: [
    {type: 'doc', id: 'README', label: 'Overview'},
    {type: 'category', label: 'Get started', items: ['guides/deploy', 'guides/operate-goose']},
    {type: 'category', label: 'Concepts', items: ['concepts/why-asdd', 'concepts/what-is-asdd', 'concepts/how-it-works']},
    {type: 'category', label: 'Guides', items: ['guides/adopt-govern', 'guides/operate-in-ci', 'guides/operate-other', 'guides/distribute', 'guides/governance-dashboard', 'guides/troubleshooting']},
    {type: 'category', label: 'Reference', items: ['reference/README']},
    {type: 'doc', id: 'prior-art', label: 'Prior art'},
    {type: 'doc', id: 'contributing-to-asdd', label: 'Contributing'},
  ],
};
module.exports = sidebars;
