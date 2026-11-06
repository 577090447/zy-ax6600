'use strict';
'require baseclass';
'require rpc';

return baseclass.extend({
  title: _('OAF / NSS 切换'),
  description: _('开启应用过滤(OAF)时自动关闭 NSS 硬件加速；关闭 OAF 后自动恢复 NSS。'),
  pollInterval: 3,

  load: function () {
    this.rpc = rpc.declare({
      object: 'luci.oaf_nss',
      method: 'state',
      expect: { '*': {} }
    });
    this.rpcToggle = rpc.declare({
      object: 'luci.oaf_nss',
      method: 'toggle',
      params: ['enable'],
      expect: { '*': {} }
    });
    return this.rpc();
  },

  render: function (data) {
    var self = this, s = data || {};

    var nssBadge = E('span', {
      'class': 'label label-' + (s.nss_running ? 'success' : 'danger')
    }, s.nss_running ? _('运行中') : _('已停止'));

    var oafBadge = E('span', {
      'class': 'label label-' + (s.oaf_running ? 'success' : 'default')
    }, s.oaf_running ? _('运行中') : _('已停止'));

    var hint = E('p', { 'class': 'text-muted' },
      s.nss_running
        ? _('NSS 硬件加速正在工作，转发计数：%s。点击按钮将关闭 NSS 并启动 OAF。').format(s.nss_forwarded || '0')
        : _('NSS 已暂停（旁路 %s），OAF 可完整识别协议。点击按钮恢复 NSS。').format(s.ecm_bypassed ? _('生效') : _('未确认'))
    );

    this.toggle = E('button', {
      'class': 'btn btn-' + (s.nss_running ? 'warning' : 'primary'),
      'click': function () { self._toggle(!s.nss_running); }
    }, s.nss_running ? _('关闭 NSS，启动 OAF') : _('关闭 OAF，恢复 NSS'));

    return E('div', { 'class': 'cbi-map' }, [
      E('div', { 'class': 'cbi-section' }, [
        E('h3', {}, _('当前状态')),
        E('table', { 'class': 'table' }, [
          E('tr', {}, [E('td', {}, _('NSS 加速')), E('td', {}, [nssBadge])]),
          E('tr', {}, [E('td', {}, _('OAF 应用过滤')), E('td', {}, [oafBadge])]),
          E('tr', {}, [E('td', {}, _('OAF 开机自启')), E('td', {}, [
            E('span', { 'class': 'label label-' + (s.oaf_enabled ? 'info' : 'default') },
              s.oaf_enabled ? _('是') : _('否'))
          ])])
        ]),
        hint,
        E('hr'),
        this.toggle,
        E('p', { 'class': 'text-muted' }, _('操作会同时写入开机自启状态：开 OAF 即设为自启，关 OAF 即取消自启。'))
      ])
    ]);
  },

  _toggle: function (enable) {
    var self = this, btn = this.toggle;
    btn.disabled = true;
    btn.innerHTML = _('处理中…');
    this.rpcToggle(enable).then(function (d) {
      btn.disabled = false;
      self.render(d);
    }).catch(function (e) {
      btn.disabled = false;
      alert(_('操作失败：%s').format(e.message || e));
    });
  }
});
