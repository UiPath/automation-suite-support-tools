"use strict";(self.webpackChunkdocs_website=self.webpackChunkdocs_website||[]).push([[278],{6259:(e,t,n)=>{n.r(t),n.d(t,{assets:()=>i,contentTitle:()=>r,default:()=>d,frontMatter:()=>a,metadata:()=>c,toc:()=>u});var s=n(5893),o=n(1151);const a={sidebar_position:1},r="AutomationSuite Cheat Sheet",c={id:"as-cheat-sheet",title:"AutomationSuite Cheat Sheet",description:"Glossary of frequently used commands",source:"@site/docs/as-cheat-sheet.md",sourceDirName:".",slug:"/as-cheat-sheet",permalink:"/automation-suite-support-tools/docs/as-cheat-sheet",draft:!1,unlisted:!1,editUrl:"https://github.com/facebook/docusaurus/tree/main/packages/create-docusaurus/templates/shared/docs/as-cheat-sheet.md",tags:[],version:"current",sidebarPosition:1,frontMatter:{sidebar_position:1},sidebar:"tutorialSidebar"},i={},u=[{value:"Set kubecontext",id:"set-kubecontext",level:2},{value:"RKE2 Config File Locations",id:"rke2-config-file-locations",level:2}];function l(e){const t={code:"code",h1:"h1",h2:"h2",p:"p",pre:"pre",...(0,o.a)(),...e.components};return(0,s.jsxs)(s.Fragment,{children:[(0,s.jsx)(t.h1,{id:"automationsuite-cheat-sheet",children:"AutomationSuite Cheat Sheet"}),"\n",(0,s.jsx)(t.p,{children:"Glossary of frequently used commands"}),"\n",(0,s.jsx)(t.h2,{id:"set-kubecontext",children:"Set kubecontext"}),"\n",(0,s.jsx)(t.pre,{children:(0,s.jsx)(t.code,{className:"language-bash",children:"export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin\n\nOn Agent Nodes,\nexport KUBECONFIG=/var/lib/rancher/rke2/agent/kubelet.kubeconfig PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin\n"})}),"\n",(0,s.jsx)(t.h2,{id:"rke2-config-file-locations",children:"RKE2 Config File Locations"}),"\n",(0,s.jsx)(t.pre,{children:(0,s.jsx)(t.code,{className:"language-bash",children:"cat /etc/rancher/rke2/config.yaml\nls /etc/rancher/rke2/rke2.yaml\n"})})]})}function d(e={}){const{wrapper:t}={...(0,o.a)(),...e.components};return t?(0,s.jsx)(t,{...e,children:(0,s.jsx)(l,{...e})}):l(e)}},1151:(e,t,n)=>{n.d(t,{Z:()=>c,a:()=>r});var s=n(7294);const o={},a=s.createContext(o);function r(e){const t=s.useContext(a);return s.useMemo((function(){return"function"==typeof e?e(t):{...t,...e}}),[t,e])}function c(e){let t;return t=e.disableParentContext?"function"==typeof e.components?e.components(o):e.components||o:r(e.components),s.createElement(a.Provider,{value:t},e.children)}}}]);